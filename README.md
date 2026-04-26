# Burned area mapping models for Sentinel-2

This repository contains the **R workflow used for burned-area model development and evaluation** in the MIGARS paper:

**“How efficient are burnt area mapping models?”**

The code has been reorganized into a public, repository-friendly structure so that the processing, threshold-based modelling, machine-learning modelling, and error-correlation analysis are easier to understand and reproduce.

## Important note on data availability

The **raw Sentinel-2 image stacks and binary burn masks are not included in this repository**.

This public repository is therefore a **code-only release**. The scripts are written so that the workflow can still be reproduced by anyone who has access to the corresponding input imagery and mask rasters in the required folder structure.

The repository also **does not include the full processed pixel tables**, because those files are very large.

## Repository structure

```text
. 
│   ├── 01_data_prep.R
│   ├── 02_threshold_models.R
│   ├── 03_ml_models.R
│	└── utils.R
```

## What each script does

### `scripts/01_data_prep.R`
Builds pixel-level analysis tables from multi-band Sentinel-2 stacks and corresponding binary burn masks.
Outputs:
- `data/processed/ard_burned_dn.csv`
- `data/processed/ard_burned_ref.csv`
- `data/processed/ard_burned_features.csv`

This script:
- reads the image/mask pairs listed in `data/raw/file_pairs.csv`
- resamples spectral bands to the mask grid
- extracts pixel values
- converts digital numbers to reflectance
- computes burned-area indices used in the paper

### `scripts/02_threshold_models.R`
Fits **single-variable threshold models** for:
- spectral bands
- burned-area indices

Outputs:
- `outputs/tables/threshold_model_summary.csv`
- `outputs/tables/threshold_test_predictions.csv`

This script:
- performs the train/test split
- searches for the best threshold using the metric defined in `config.R`
- evaluates the threshold model on the held-out test set

### `scripts/03_ml_models.R`
Fits **Random Forest** and **XGBoost** models using the six reflectance bands.

Outputs:
- `outputs/models/rf_model.rds`
- `outputs/models/xgboost_model.rds`
- `outputs/tables/ml_model_summary.csv`
- `outputs/tables/ml_test_predictions.csv`
- `outputs/tables/all_test_predictions.csv`
- `outputs/tables/error_correlation_matrix.csv`

This script:
- uses the same train/test split settings as the threshold workflow
- trains RF and XGBoost with cross-validation
- saves model objects and predictions
- computes the error-correlation matrix across available model predictions

## Required input layout

Place your local input files under `data/raw/`, then create:

- `data/raw/file_pairs.csv`

The CSV must contain the following columns:

```csv
image_file,mask_file
s2/scene_01.tif,masks/scene_01_mask.tif
s2/scene_02.tif,masks/scene_02_mask.tif
```

The paths in `file_pairs.csv` are **relative to `data/raw/`**.

A blank template is provided as:
- `data/raw/file_pairs_template.csv`

## Expected raster format

The preparation script assumes that each image listed in `image_file` is a **multi-band raster stack** containing the six Sentinel-2 bands used in the study.

By default, the band positions are defined in `config.R` as:

```r
stack_band_positions <- c(1, 2, 3, 4, 5, 6)
raw_band_names <- c("B2", "B3", "B4", "B8", "B11", "B12")
```

If your stack uses a different layer order, edit these values in `config.R`.

## Packages

Install the required packages in R before running the scripts:

```r
install.packages(c(
  "terra", "dplyr", "readr", "caret", "pROC",
  "randomForest", "xgboost", "foreach", "doParallel"
))
```

## How to run

From the repository root:

```r
source("scripts/01_data_prep.R")
source("scripts/02_threshold_models.R")
source("scripts/03_ml_models.R")
```

Or from the command line:

```bash
Rscript scripts/01_data_prep.R
Rscript scripts/02_threshold_models.R
Rscript scripts/03_ml_models.R
```

## Key settings to edit before running

Open `config.R` and adjust these settings as needed:
- `train_fraction`
- `threshold_metric`
- `stack_band_positions`
- `reflectance_scale_factor`
- `rf_mtry_grid`
- `xgb_grid`
- `use_parallel`
- `n_cores`

## What is not included here

This repository intentionally does **not** include:
- raw Sentinel-2 imagery
- raw mask rasters
- very large intermediate pixel tables
- manuscript figures exported from the private working environment
