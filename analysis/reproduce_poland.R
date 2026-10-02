#!/usr/bin/env Rscript

# Reproduce the complete Poland reference experiment from the installed
# cropyieldmodel package. The wrapper reproduce.ps1 installs the current source
# tree into an isolated project library before executing this file.

arguments <- commandArgs(trailingOnly = TRUE)
values <- list(
  crop = "barley", harvest_month = 6L,
  last_yield_year = 2018L, predict_through = 2019L,
  output_dir = file.path("outputs", "package_reference")
)
for (argument in arguments) {
  if (!startsWith(argument, "--") || !grepl("=", argument, fixed = TRUE)) {
    stop("Arguments must use --name=value: ", argument, call. = FALSE)
  }
  pieces <- strsplit(sub("^--", "", argument), "=", fixed = TRUE)[[1]]
  key <- gsub("-", "_", pieces[1], fixed = TRUE)
  values[[key]] <- paste(pieces[-1], collapse = "=")
}
values$harvest_month <- as.integer(values$harvest_month)
values$last_yield_year <- as.integer(values$last_yield_year)
values$predict_through <- as.integer(values$predict_through)

suppressPackageStartupMessages(library(cropyieldmodel))
comparison <- run_crop_workflow(
  data_dir = poland_example_path(),
  crop = values$crop,
  harvest_month = values$harvest_month,
  output_dir = values$output_dir,
  config = crop_model_config(),
  last_yield_year = values$last_yield_year,
  predict_through = values$predict_through,
  verbose = TRUE,
  overwrite = TRUE
)
print(comparison)
