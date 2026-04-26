# 03_ml_models.R --------------------------------------------------------------
# Fits Random Forest and XGBoost models, writes predictions, and computes
# an error-correlation matrix using the threshold-model predictions if available.
#
# Outputs:
#   outputs/models/rf_model.rds
#   outputs/models/xgboost_model.rds
#   outputs/tables/ml_model_summary.csv
#   outputs/tables/ml_test_predictions.csv
#   outputs/tables/all_test_predictions.csv
#   outputs/tables/error_correlation_matrix.csv

get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_flag <- "--file="
  match <- grep(file_flag, cmd_args)
  if (length(match) == 0) return(normalizePath(".", winslash = "/", mustWork = FALSE))
  normalizePath(dirname(sub(file_flag, "", cmd_args[match[1]])), winslash = "/", mustWork = FALSE)
}

repo_dir <- normalizePath(file.path(get_script_dir(), ".."), winslash = "/", mustWork = FALSE)
source(file.path(repo_dir, "config.R"))
source(file.path(repo_dir, "R", "utils.R"))

required_pkgs <- c("readr", "dplyr", "caret", "pROC", "randomForest", "xgboost", "foreach")
require_packages(required_pkgs)

input_file <- file.path(dirs$data_processed, "ard_burned_features.csv")
if (!file.exists(input_file)) {
  stop("Missing input file: data/processed/ard_burned_features.csv.\nRun scripts/01_data_prep.R first.", call. = FALSE)
}

data <- readr::read_csv(input_file, show_col_types = FALSE)
data$.row_id <- seq_len(nrow(data))
data$burned <- make_class_factor(data$burned, positive = positive_class, negative = negative_class)

split <- stratified_split(data, outcome = "burned", p = train_fraction, seed = seed)
train_df <- split$train
test_df  <- split$test

predictor_vars <- reflectance_band_names

control <- caret::trainControl(
  method = "cv",
  number = cv_folds,
  classProbs = TRUE,
  summaryFunction = caret::twoClassSummary,
  savePredictions = "final"
)

parallel_cluster <- prepare_parallel_backend(use_parallel = use_parallel, n_cores = n_cores)
on.exit(stop_parallel_backend(parallel_cluster), add = TRUE)

# Random Forest ----------------------------------------------------------------
set.seed(seed)
rf_model <- caret::train(
  x = train_df[, predictor_vars, drop = FALSE],
  y = train_df$burned,
  method = "rf",
  metric = "ROC",
  trControl = control,
  tuneGrid = expand.grid(mtry = rf_mtry_grid),
  ntree = rf_ntree,
  importance = TRUE
)

rf_train_prob <- predict(rf_model, newdata = train_df, type = "prob")[, positive_class]
rf_train_pred <- predict(rf_model, newdata = train_df)
rf_test_prob  <- predict(rf_model, newdata = test_df, type = "prob")[, positive_class]
rf_test_pred  <- predict(rf_model, newdata = test_df)

rf_train_metrics <- cbind(
  data.frame(Model = "RandomForest", Dataset = "train", stringsAsFactors = FALSE),
  evaluate_predictions(train_df$burned, rf_train_pred, rf_train_prob, positive = positive_class)
)

rf_test_metrics <- cbind(
  data.frame(Model = "RandomForest", Dataset = "test", stringsAsFactors = FALSE),
  evaluate_predictions(test_df$burned, rf_test_pred, rf_test_prob, positive = positive_class)
)

# XGBoost ----------------------------------------------------------------------
set.seed(seed)
xgb_model <- caret::train(
  x = train_df[, predictor_vars, drop = FALSE],
  y = train_df$burned,
  method = "xgbTree",
  metric = "ROC",
  trControl = control,
  tuneGrid = xgb_grid
)

xgb_train_prob <- predict(xgb_model, newdata = train_df, type = "prob")[, positive_class]
xgb_train_pred <- predict(xgb_model, newdata = train_df)
xgb_test_prob  <- predict(xgb_model, newdata = test_df, type = "prob")[, positive_class]
xgb_test_pred  <- predict(xgb_model, newdata = test_df)

xgb_train_metrics <- cbind(
  data.frame(Model = "XGBoost", Dataset = "train", stringsAsFactors = FALSE),
  evaluate_predictions(train_df$burned, xgb_train_pred, xgb_train_prob, positive = positive_class)
)

xgb_test_metrics <- cbind(
  data.frame(Model = "XGBoost", Dataset = "test", stringsAsFactors = FALSE),
  evaluate_predictions(test_df$burned, xgb_test_pred, xgb_test_prob, positive = positive_class)
)

# Save model objects -----------------------------------------------------------
saveRDS(rf_model, file = file.path(dirs$outputs_models, "rf_model.rds"))
saveRDS(xgb_model, file = file.path(dirs$outputs_models, "xgboost_model.rds"))

# Save summaries ----------------------------------------------------------------
ml_summary <- dplyr::bind_rows(
  rf_train_metrics,
  rf_test_metrics,
  xgb_train_metrics,
  xgb_test_metrics
)

ml_summary_file <- file.path(dirs$outputs_tables, "ml_model_summary.csv")
readr::write_csv(ml_summary, ml_summary_file)

ml_preds <- data.frame(
  .row_id = test_df$.row_id,
  observed = test_df$burned,
  rf_prob = rf_test_prob,
  rf_pred = rf_test_pred,
  xgb_prob = xgb_test_prob,
  xgb_pred = xgb_test_pred,
  stringsAsFactors = FALSE
)

ml_pred_file <- file.path(dirs$outputs_tables, "ml_test_predictions.csv")
readr::write_csv(ml_preds, ml_pred_file)

# Merge threshold predictions if available -------------------------------------
threshold_pred_file <- file.path(dirs$outputs_tables, "threshold_test_predictions.csv")
all_preds <- ml_preds

if (file.exists(threshold_pred_file)) {
  threshold_preds <- readr::read_csv(threshold_pred_file, show_col_types = FALSE)
  all_preds <- dplyr::left_join(
    threshold_preds,
    dplyr::select(ml_preds, .row_id, rf_prob, rf_pred, xgb_prob, xgb_pred),
    by = ".row_id"
  )
}

all_pred_file <- file.path(dirs$outputs_tables, "all_test_predictions.csv")
readr::write_csv(all_preds, all_pred_file)

# Error correlation analysis ---------------------------------------------------
truth_num <- to_binary(all_preds$observed, positive = positive_class)

prediction_cols <- setdiff(names(all_preds), c(".row_id", "observed", "rf_prob", "xgb_prob"))

error_df <- lapply(prediction_cols, function(col_name) {
  pred_num <- to_binary(all_preds[[col_name]], positive = positive_class)
  pred_num - truth_num
})
error_df <- as.data.frame(error_df)
names(error_df) <- prediction_cols

error_corr <- stats::cor(error_df, use = "pairwise.complete.obs")
error_corr_file <- file.path(dirs$outputs_tables, "error_correlation_matrix.csv")
readr::write_csv(
  cbind(Model = rownames(error_corr), as.data.frame(error_corr)),
  error_corr_file
)

message("Done.")
message("Created:")
message(" - ", ml_summary_file)
message(" - ", ml_pred_file)
message(" - ", all_pred_file)
message(" - ", error_corr_file)
message(" - ", file.path(dirs$outputs_models, "rf_model.rds"))
message(" - ", file.path(dirs$outputs_models, "xgboost_model.rds"))
