# 02_threshold_models.R -------------------------------------------------------
# Computes single-variable threshold models for spectral bands and fire indices.
# Outputs:
#   outputs/tables/threshold_model_summary.csv
#   outputs/tables/threshold_test_predictions.csv

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

required_pkgs <- c("readr", "dplyr", "caret", "pROC")
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

threshold_vars <- c(
  reflectance_band_names,
  c("BAI", "MIRBI", "NBR1", "NBR2", "NDSWIR", "CSI", "CSI2", "FSI", "MBAIS2", "NBR_plus")
)

missing_threshold_vars <- setdiff(threshold_vars, names(train_df))
if (length(missing_threshold_vars) > 0) {
  stop("Missing variables required for threshold modelling: ",
       paste(missing_threshold_vars, collapse = ", "),
       call. = FALSE)
}

summary_rows <- list()
predictions_df <- data.frame(
  .row_id = test_df$.row_id,
  observed = test_df$burned,
  stringsAsFactors = FALSE
)

for (var_name in threshold_vars) {
  rule <- find_best_threshold(
    scores = train_df[[var_name]],
    truth = train_df$burned,
    metric = threshold_metric,
    quantile_grid = threshold_quantile_grid
  )

  pred_test <- apply_threshold_rule(
    scores = test_df[[var_name]],
    threshold = rule$threshold,
    operator = rule$operator,
    positive = positive_class,
    negative = negative_class
  )

  metrics <- evaluate_predictions(
    obs = test_df$burned,
    pred = pred_test,
    prob = NULL,
    positive = positive_class
  )

  score_auc <- suppressWarnings(
    as.numeric(pROC::auc(
      pROC::roc(
        response = test_df$burned,
        predictor = if (rule$operator == ">=") test_df[[var_name]] else -test_df[[var_name]],
        levels = rev(levels(test_df$burned)),
        quiet = TRUE
      )
    ))
  )

  summary_rows[[var_name]] <- cbind(
    data.frame(
      Model = var_name,
      Threshold = rule$threshold,
      Operator = rule$operator,
      Selection_metric = threshold_metric,
      AUC_score = score_auc,
      stringsAsFactors = FALSE
    ),
    metrics
  )

  predictions_df[[var_name]] <- pred_test
}

summary_df <- dplyr::bind_rows(summary_rows) |>
  dplyr::arrange(dplyr::desc(Balanced_Accuracy), dplyr::desc(F1))

summary_file <- file.path(dirs$outputs_tables, "threshold_model_summary.csv")
pred_file <- file.path(dirs$outputs_tables, "threshold_test_predictions.csv")

readr::write_csv(summary_df, summary_file)
readr::write_csv(predictions_df, pred_file)

message("Done.")
message("Created:")
message(" - ", summary_file)
message(" - ", pred_file)
