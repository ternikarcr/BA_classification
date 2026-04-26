# Helper functions ------------------------------------------------------------

require_packages <- function(packages) {
  missing_pkgs <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs) > 0) {
    stop(
      "Missing packages: ",
      paste(missing_pkgs, collapse = ", "),
      "\nInstall them first with install.packages(...).",
      call. = FALSE
    )
  }
}

safe_divide <- function(num, den) {
  ifelse(is.na(den) | den == 0, NA_real_, num / den)
}

to_binary <- function(y, positive = "Burned") {
  if (is.factor(y)) {
    return(ifelse(as.character(y) == positive, 1, 0))
  }
  if (is.character(y)) {
    return(ifelse(y == positive, 1, 0))
  }
  if (is.logical(y)) {
    return(as.integer(y))
  }
  as.integer(y)
}

make_class_factor <- function(y, positive = "Burned", negative = "NonBurned") {
  y_bin <- to_binary(y, positive = positive)
  factor(ifelse(y_bin == 1, positive, negative), levels = c(negative, positive))
}

precision_recall_f1 <- function(truth, pred_positive) {
  tp <- sum(pred_positive == 1 & truth == 1, na.rm = TRUE)
  fp <- sum(pred_positive == 1 & truth == 0, na.rm = TRUE)
  fn <- sum(pred_positive == 0 & truth == 1, na.rm = TRUE)

  precision <- safe_divide(tp, tp + fp)
  recall <- safe_divide(tp, tp + fn)
  f1 <- if (is.na(precision) || is.na(recall) || (precision + recall) == 0) {
    NA_real_
  } else {
    2 * precision * recall / (precision + recall)
  }

  c(precision = precision, recall = recall, f1 = f1)
}

compute_fire_indices <- function(df, eps = 0.01) {
  required_cols <- c("blue", "green", "red", "nir", "swir1", "swir2")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0) {
    stop("Missing required reflectance columns: ", paste(missing_cols, collapse = ", "), call. = FALSE)
  }

  out <- df
  out$BAI <- 1 / (((0.1 - out$red) ^ 2) + ((0.06 - out$nir) ^ 2))
  out$MIRBI <- (10 * out$swir2) - (9.8 * out$swir1) + 2
  out$NBR1 <- (out$swir2 - out$nir) / (out$swir2 + out$nir)
  out$NBR2 <- (out$swir2 - out$swir1 - 0.02) / (out$swir2 + out$swir1 + 0.1)
  out$NDSWIR <- (out$swir1 - out$nir) / (out$swir1 + out$nir)
  out$CSI <- (out$swir1 - out$red) / (out$swir1 + out$red)
  out$CSI2 <- out$nir / (out$swir2 + eps)
  out$FSI <- out$swir1 / (out$nir + eps)
  out$MBAIS2 <- (1 - sqrt(out$red * out$nir)) *
    (((out$swir2 - out$nir) / sqrt(out$swir2 + out$nir)) + 1)
  out$NBR_plus <- (out$swir2 - out$nir - out$green - out$blue) /
    (out$swir2 + out$nir + out$green + out$blue)

  out
}

stratified_split <- function(data, outcome, p = 0.70, seed = 107) {
  set.seed(seed)
  idx <- caret::createDataPartition(y = data[[outcome]], p = p, list = FALSE)
  list(
    train = data[idx, , drop = FALSE],
    test  = data[-idx, , drop = FALSE]
  )
}

evaluate_predictions <- function(obs, pred, prob = NULL, positive = "Burned") {
  obs <- make_class_factor(obs, positive = positive)
  pred <- make_class_factor(pred, positive = positive)

  cm <- caret::confusionMatrix(data = pred, reference = obs, positive = positive)

  auc_value <- NA_real_
  if (!is.null(prob)) {
    roc_obj <- pROC::roc(response = obs, predictor = prob,
                         levels = rev(levels(obs)), quiet = TRUE)
    auc_value <- as.numeric(pROC::auc(roc_obj))
  }

  data.frame(
    Sensitivity = unname(cm$byClass["Sensitivity"]),
    Specificity = unname(cm$byClass["Specificity"]),
    Pos_Pred_Value = unname(cm$byClass["Pos Pred Value"]),
    Neg_Pred_Value = unname(cm$byClass["Neg Pred Value"]),
    Precision = unname(cm$byClass["Precision"]),
    Recall = unname(cm$byClass["Recall"]),
    F1 = unname(cm$byClass["F1"]),
    Prevalence = unname(cm$byClass["Prevalence"]),
    Detection_Rate = unname(cm$byClass["Detection Rate"]),
    Detection_Prevalence = unname(cm$byClass["Detection Prevalence"]),
    Balanced_Accuracy = unname(cm$byClass["Balanced Accuracy"]),
    Kappa = unname(cm$overall["Kappa"]),
    AUC = auc_value,
    row.names = NULL
  )
}

find_best_threshold <- function(scores, truth, metric = c("f1", "youden"), quantile_grid = seq(0, 1, 0.01)) {
  metric <- match.arg(metric)
  truth_bin <- to_binary(truth)
  scores <- as.numeric(scores)

  keep <- is.finite(scores) & !is.na(truth_bin)
  truth_bin <- truth_bin[keep]
  scores <- scores[keep]

  thresholds <- unique(as.numeric(stats::quantile(scores, probs = quantile_grid, na.rm = TRUE)))
  thresholds <- thresholds[is.finite(thresholds)]

  evaluate_rule <- function(operator) {
    metric_values <- vapply(thresholds, function(th) {
      pred <- if (operator == ">=") as.integer(scores >= th) else as.integer(scores <= th)

      if (metric == "f1") {
        precision_recall_f1(truth_bin, pred)[["f1"]]
      } else {
        tp <- sum(pred == 1 & truth_bin == 1)
        fp <- sum(pred == 1 & truth_bin == 0)
        tn <- sum(pred == 0 & truth_bin == 0)
        fn <- sum(pred == 0 & truth_bin == 1)
        sensitivity <- safe_divide(tp, tp + fn)
        specificity <- safe_divide(tn, tn + fp)
        sensitivity + specificity - 1
      }
    }, numeric(1))

    best_idx <- which.max(metric_values)
    data.frame(
      threshold = thresholds[best_idx],
      operator = operator,
      score = metric_values[best_idx],
      stringsAsFactors = FALSE
    )
  }

  candidates <- rbind(
    evaluate_rule(">="),
    evaluate_rule("<=")
  )

  candidates[which.max(candidates$score), , drop = FALSE]
}

apply_threshold_rule <- function(scores, threshold, operator = ">=", positive = "Burned", negative = "NonBurned") {
  pred_bin <- if (operator == ">=") {
    as.integer(scores >= threshold)
  } else {
    as.integer(scores <= threshold)
  }

  factor(ifelse(pred_bin == 1, positive, negative), levels = c(negative, positive))
}

prepare_parallel_backend <- function(use_parallel = TRUE, n_cores = 1) {
  if (!use_parallel) return(NULL)
  if (!requireNamespace("doParallel", quietly = TRUE)) return(NULL)

  cl <- parallel::makeCluster(n_cores)
  doParallel::registerDoParallel(cl)
  cl
}

stop_parallel_backend <- function(cl) {
  if (!is.null(cl)) {
    parallel::stopCluster(cl)
    foreach::registerDoSEQ()
  }
}
