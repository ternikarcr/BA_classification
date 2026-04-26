# 01_data_prep.R --------------------------------------------------------------
# Builds pixel tables from Sentinel-2 image stacks and binary burn masks.
# Expected input:
#   data/raw/file_pairs.csv
# with columns:
#   image_file,mask_file
#
# The file paths in file_pairs.csv should be relative to data/raw/.
# Example:
#   image_file,mask_file
#   s2/scene_01.tif,masks/scene_01_mask.tif

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

required_pkgs <- c("terra", "dplyr", "readr")
require_packages(required_pkgs)

pairs_file <- file.path(dirs$data_raw, "file_pairs.csv")
if (!file.exists(pairs_file)) {
  stop(
    "Missing file_pairs.csv in data/raw/.\n",
    "Copy data/raw/file_pairs_template.csv to data/raw/file_pairs.csv and edit the filenames.",
    call. = FALSE
  )
}

file_pairs <- readr::read_csv(pairs_file, show_col_types = FALSE)

required_cols <- c("image_file", "mask_file")
missing_cols <- setdiff(required_cols, names(file_pairs))
if (length(missing_cols) > 0) {
  stop("file_pairs.csv must contain columns: image_file, mask_file", call. = FALSE)
}

message("Reading raster pairs and extracting pixel tables ...")

pair_tables <- vector("list", length = nrow(file_pairs))

for (i in seq_len(nrow(file_pairs))) {
  image_path <- file.path(dirs$data_raw, file_pairs$image_file[i])
  mask_path  <- file.path(dirs$data_raw, file_pairs$mask_file[i])

  if (!file.exists(image_path)) stop("Image not found: ", image_path, call. = FALSE)
  if (!file.exists(mask_path)) stop("Mask not found: ", mask_path, call. = FALSE)

  image_stack <- terra::rast(image_path)
  burn_mask   <- terra::rast(mask_path)

  if (terra::nlyr(image_stack) < max(stack_band_positions)) {
    stop("Image stack has fewer layers than stack_band_positions requires: ", image_path, call. = FALSE)
  }

  image_stack <- image_stack[[stack_band_positions]]
  names(image_stack) <- raw_band_names

  image_resampled <- terra::resample(image_stack, burn_mask, method = "bilinear")

  band_values <- as.data.frame(terra::values(image_resampled, mat = FALSE))
  burn_values <- terra::values(burn_mask, mat = FALSE)[, 1]

  burn_values[is.na(burn_values)] <- 0
  burn_values[!(burn_values %in% c(0, 1))] <- NA

  pair_df <- dplyr::bind_cols(
    data.frame(burned = burn_values),
    band_values
  )

  if (isTRUE(export_xy_coordinates)) {
    xy <- terra::xyFromCell(burn_mask, seq_len(terra::ncell(burn_mask)))
    pair_df$x <- xy[, 1]
    pair_df$y <- xy[, 2]
  }

  pair_df$scene_id <- tools::file_path_sans_ext(basename(file_pairs$image_file[i]))
  pair_tables[[i]] <- pair_df

  per_scene_csv <- file.path(
    dirs$data_processed,
    paste0(pair_df$scene_id[1], "_pixels.csv")
  )
  readr::write_csv(pair_df, per_scene_csv)
  message(sprintf("  [%d/%d] Wrote %s", i, nrow(file_pairs), basename(per_scene_csv)))
}

dn_df <- dplyr::bind_rows(pair_tables)
dn_df <- dn_df |>
  dplyr::filter(!is.na(burned)) |>
  dplyr::mutate(
    burned = as.integer(burned)
  )

dn_output <- file.path(dirs$data_processed, "ard_burned_dn.csv")
readr::write_csv(dn_df, dn_output)

reflectance_df <- dn_df

for (i in seq_along(raw_band_names)) {
  old_name <- raw_band_names[i]
  new_name <- reflectance_band_names[i]
  reflectance_df[[new_name]] <- reflectance_df[[old_name]] / reflectance_scale_factor
}

reflectance_df <- reflectance_df |>
  dplyr::select(-dplyr::all_of(raw_band_names))

reflectance_output <- file.path(dirs$data_processed, "ard_burned_ref.csv")
readr::write_csv(reflectance_df, reflectance_output)

feature_df <- compute_fire_indices(reflectance_df)
features_output <- file.path(dirs$data_processed, "ard_burned_features.csv")
readr::write_csv(feature_df, features_output)

message("Done.")
message("Created:")
message(" - ", dn_output)
message(" - ", reflectance_output)
message(" - ", features_output)
