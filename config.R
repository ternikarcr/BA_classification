# Project configuration -------------------------------------------------------

# Root directory of the repository. This file is expected to live in the
# repository root, so "." works when scripts are run with Rscript.
if (!exists("root_dir", inherits = FALSE)) {
  root_dir <- normalizePath(".", winslash = "/", mustWork = FALSE)
}

dirs <- list(
  data_raw       = file.path(root_dir, "data", "raw"),
  data_processed = file.path(root_dir, "data", "processed"),
  outputs_tables = file.path(root_dir, "outputs", "tables"),
  outputs_models = file.path(root_dir, "outputs", "models"),
  outputs_figures = file.path(root_dir, "outputs", "figures")
)

# Ensure required folders exist.
for (dir_path in unname(unlist(dirs))) {
  if (!dir.exists(dir_path)) dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)
}

# Study settings --------------------------------------------------------------

seed <- 107
train_fraction <- 0.70

negative_class <- "NonBurned"
positive_class <- "Burned"

# Raw Sentinel-2 stack settings. These positions refer to the layers in each
# multi-band image stack listed in data/raw/file_pairs.csv.
stack_band_positions <- c(1, 2, 3, 4, 5, 6)
raw_band_names <- c("B2", "B3", "B4", "B8", "B11", "B12")
reflectance_band_names <- c("blue", "green", "red", "nir", "swir1", "swir2")
reflectance_scale_factor <- 10000

# Set to TRUE if x/y coordinates should be exported in the processed tables.
export_xy_coordinates <- TRUE

# Threshold search settings ---------------------------------------------------

# Supported metrics: "f1" or "youden"
threshold_metric <- "f1"

# Thresholds are searched over quantiles for computational efficiency on very
# large pixel tables. Increase the resolution if needed.
threshold_quantile_grid <- seq(0, 1, by = 0.01)

# Machine-learning settings ---------------------------------------------------

cv_folds <- 5
use_parallel <- TRUE
n_cores <- max(1, floor(parallel::detectCores() / 2))

rf_ntree <- 500
rf_mtry_grid <- c(2)

xgb_grid <- expand.grid(
  nrounds = 100,
  max_depth = c(3, 5, 7),
  eta = c(0.01, 0.10, 0.30),
  gamma = 0,
  colsample_bytree = 0.8,
  min_child_weight = 1,
  subsample = 0.8
)
