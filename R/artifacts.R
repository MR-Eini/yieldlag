cy_known_artifacts <- function() {
  c(
    "analysis_config.dput", "analysis_config.rds", "artifact_checksums.csv",
    "all_tuning_results.csv", "ensemble_weights.csv", "fitted_models.rds",
    "input_checksums.csv", "latest_national_forecast.csv",
    "method_comparison.png", "method_selection_tuning.csv",
    "metrics_by_region.csv", "metrics_by_year.csv", "model_comparison.rds",
    "model_metrics.csv", "monthly_coefficients.csv", "monthly_coefficients.png",
    "national_cv_predictions.csv", "national_predictions.csv",
    "national_predictions.png", "province_cv_predictions.csv",
    "province_predictions.csv", "report.md", "run_manifest.txt",
    "selected_hyperparameters.csv", "session_info.txt",
    "weather_feature_manifest.csv", "stress_basis_coefficients.csv",
    "prediction_support.csv", "stress_prediction_components.csv"
  )
}

cy_input_checksums <- function(provenance) {
  paths <- unique(unlist(provenance[c("yield_file", "area_file", "weather_files")],
    use.names = FALSE))
  if (is.null(paths)) paths <- character()
  paths <- as.character(paths)
  paths <- paths[file.exists(paths)]
  if (!length(paths)) {
    return(data.frame(File = character(), MD5 = character(), stringsAsFactors = FALSE))
  }
  data.frame(
    File = normalizePath(paths, winslash = "/"),
    MD5 = unname(tools::md5sum(paths)),
    stringsAsFactors = FALSE
  )
}

cy_selected_parameters <- function(x) {
  do.call(rbind, lapply(x$results, function(result) {
    data.frame(
      Method = result$method,
      Parameters = cy_params_string(result$selected_params),
      PredictiveSigma = result$predictive_sigma,
      IntervalLevel = x$config$interval_level,
      IntervalHalfWidth = result$interval_half_width_80,
      SelectedByTuning = result$method == x$selected_method,
      stringsAsFactors = FALSE
    )
  }))
}

cy_write_comparison_report <- function(x, path, selected_parameters, ensemble_weights) {
  selected_evaluation <- x$metrics[
    x$metrics$Method == x$selected_method, , drop = FALSE
  ]
  lines <- c(
    "# YieldLag model comparison",
    "",
    paste("- Crop:", x$crop),
    paste("- Agricultural-year endpoint month:", x$harvest_month),
    paste("- Training cutoff:", x$last_yield_year),
    paste("- Tuning years:", paste(x$year_split$tuning, collapse = ", ")),
    paste("- Later evaluation years:", paste(x$year_split$evaluation, collapse = ", ")),
    paste("- Prediction through:", x$predict_through),
    paste("- National aggregation:", x$aggregation),
    paste("- Runtime (seconds):", round(x$runtime_seconds, 3)),
    "",
    "## Pre-declared automatic selection",
    "",
    paste0(
      "The method selected using province-year tuning RMSE only is **",
      x$selected_method, "**. Later evaluation results were not used for this selection."
    ),
    "",
    "### Tuning-period method comparison",
    "",
    "```",
    capture.output(print(x$tuning_method_metrics, row.names = FALSE)),
    "```",
    "",
    "### Later performance of the tuning-selected method",
    "",
    "```",
    capture.output(print(selected_evaluation, row.names = FALSE)),
    "```",
    "",
    "## All later evaluation metrics",
    "",
    "```",
    capture.output(print(x$metrics, row.names = FALSE)),
    "```",
    "",
    "## Hyperparameters selected within each method",
    "",
    "```",
    capture.output(print(selected_parameters, row.names = FALSE)),
    "```"
  )
  if (nrow(ensemble_weights)) {
    lines <- c(lines,
      "", "## Ensemble weights", "", "```",
      capture.output(print(ensemble_weights, row.names = FALSE)), "```")
  }
  lines <- c(lines,
    "",
    "## Interpretation",
    "",
    "Each rolling fit excludes target-year yields and estimates preprocessing from its training window. Hyperparameters, ensemble settings, method selection, and interval widths are learned on the tuning block and held fixed for later evaluation.",
    "",
    "Later-period scores describe this dataset and split. Forecast errors share years and regions; metric comparisons require appropriate uncertainty estimates. Empirical interval coverage and training-range diagnostics do not provide guarantees on new populations.",
    "",
    "## Reproduction",
    "",
    "The directory contains the complete configuration (`analysis_config.dput`), input and artifact checksums, selected and rejected tuning candidates, row-level predictions, final fitted models, package and R versions, and session information."
  )
  writeLines(lines, path, useBytes = TRUE)
}

#' Write a complete reproducibility bundle
#'
#' Only named package artifacts are replaced when `overwrite = TRUE`; unrelated
#' files in the directory are never removed.
#'
#' @param x A `crop_model_comparison`.
#' @param output_dir Destination directory.
#' @param overwrite Whether existing package artifacts may be replaced.
#'
#' @return The normalized output path, invisibly.
#' @export
write_crop_results <- function(x, output_dir, overwrite = FALSE) {
  if (!inherits(x, "crop_model_comparison")) {
    stop("x must be a crop_model_comparison.", call. = FALSE)
  }
  if (length(output_dir) != 1L || is.na(output_dir) || !nzchar(output_dir)) {
    stop("output_dir must be one non-empty path.", call. = FALSE)
  }
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  output_dir <- normalizePath(output_dir, winslash = "/")
  artifact_paths <- file.path(output_dir, cy_known_artifacts())
  existing <- artifact_paths[file.exists(artifact_paths)]
  if (length(existing) && !isTRUE(overwrite)) {
    stop("Existing result artifacts found; use overwrite = TRUE to replace them.",
      call. = FALSE)
  }
  if (length(existing)) unlink(existing, force = TRUE)

  selected_parameters <- cy_selected_parameters(x)
  tuning_results <- do.call(rbind, lapply(x$results, `[[`, "tuning_table"))
  ensemble_weights <- if ("ensemble" %in% names(x$results)) {
    data.frame(
      Method = names(x$results$ensemble$weights),
      Weight = as.numeric(x$results$ensemble$weights),
      stringsAsFactors = FALSE
    )
  } else data.frame(Method = character(), Weight = numeric())
  input_checksums <- cy_input_checksums(x$provenance)
  models <- lapply(names(x$results), function(method) get_crop_model(x, method))
  names(models) <- names(x$results)
  # Diagnostic inputs are retained by the comparison constructor, not rebuilt
  # from predictions or inferred from exported row identifiers.
  if (!is.null(x$prediction_panel)) {
    support <- do.call(rbind, lapply(names(models), function(method) {
      data.frame(Method = method, prediction_support(models[[method]], x$prediction_panel))
    }))
    utils::write.csv(support, file.path(output_dir, "prediction_support.csv"), row.names = FALSE)
    if ("stress_lag" %in% names(models)) {
      utils::write.csv(cy_stress_coefficients(models$stress_lag$engine),
        file.path(output_dir, "stress_basis_coefficients.csv"), row.names = FALSE)
      utils::write.csv(explain_crop_prediction(models$stress_lag, x$prediction_panel),
        file.path(output_dir, "stress_prediction_components.csv"), row.names = FALSE)
    }
  }

  utils::write.csv(x$manifest,
    file.path(output_dir, "weather_feature_manifest.csv"), row.names = FALSE)
  utils::write.csv(input_checksums,
    file.path(output_dir, "input_checksums.csv"), row.names = FALSE)
  utils::write.csv(tuning_results,
    file.path(output_dir, "all_tuning_results.csv"), row.names = FALSE)
  utils::write.csv(x$tuning_method_metrics,
    file.path(output_dir, "method_selection_tuning.csv"), row.names = FALSE)
  utils::write.csv(selected_parameters,
    file.path(output_dir, "selected_hyperparameters.csv"), row.names = FALSE)
  utils::write.csv(ensemble_weights,
    file.path(output_dir, "ensemble_weights.csv"), row.names = FALSE)
  utils::write.csv(x$metrics,
    file.path(output_dir, "model_metrics.csv"), row.names = FALSE)
  utils::write.csv(x$metrics_by_region,
    file.path(output_dir, "metrics_by_region.csv"), row.names = FALSE)
  utils::write.csv(x$metrics_by_year,
    file.path(output_dir, "metrics_by_year.csv"), row.names = FALSE)
  utils::write.csv(x$province_cv_predictions,
    file.path(output_dir, "province_cv_predictions.csv"), row.names = FALSE)
  utils::write.csv(x$national_cv_predictions,
    file.path(output_dir, "national_cv_predictions.csv"), row.names = FALSE)
  utils::write.csv(x$province_predictions,
    file.path(output_dir, "province_predictions.csv"), row.names = FALSE)
  utils::write.csv(x$national_predictions,
    file.path(output_dir, "national_predictions.csv"), row.names = FALSE)
  utils::write.csv(x$monthly_coefficients,
    file.path(output_dir, "monthly_coefficients.csv"), row.names = FALSE)
  latest <- x$national_predictions[x$national_predictions$Year == x$predict_through, ]
  utils::write.csv(latest,
    file.path(output_dir, "latest_national_forecast.csv"), row.names = FALSE)
  saveRDS(x$config, file.path(output_dir, "analysis_config.rds"), version = 3)
  dput(x$config, file = file.path(output_dir, "analysis_config.dput"), control = "all")
  saveRDS(models, file.path(output_dir, "fitted_models.rds"), version = 3)
  saveRDS(x, file.path(output_dir, "model_comparison.rds"), version = 3)

  cy_write_comparison_report(
    x, file.path(output_dir, "report.md"), selected_parameters, ensemble_weights
  )
  cy_plot_method_comparison(x$metrics, file.path(output_dir, "method_comparison.png"))
  cy_plot_national_predictions(
    x$national_cv_predictions, x$national_predictions,
    file.path(output_dir, "national_predictions.png"),
    x$last_yield_year, x$predict_through
  )
  cy_plot_monthly_coefficients(
    x$monthly_coefficients, file.path(output_dir, "monthly_coefficients.png")
  )

  session_lines <- capture.output(utils::sessionInfo())
  writeLines(session_lines, file.path(output_dir, "session_info.txt"), useBytes = TRUE)
  manifest_lines <- c(
    paste("Run timestamp UTC:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
    paste("Package:", "yieldlag", x$package_version),
    paste("R version:", R.version.string),
    paste("Platform:", R.version$platform),
    paste("Crop:", x$crop),
    paste("Harvest month:", x$harvest_month),
    paste("Methods:", paste(names(x$results), collapse = ",")),
    paste("Method selection rule:", x$selection_rule),
    paste("Method selected from tuning:", x$selected_method),
    paste("Training cutoff:", x$last_yield_year),
    paste("Tuning years:", paste(x$year_split$tuning, collapse = ",")),
    paste("Evaluation years:", paste(x$year_split$evaluation, collapse = ",")),
    paste("Prediction through:", x$predict_through),
    paste("Runtime seconds:", round(x$runtime_seconds, 3)),
    "Algorithms use no random-number generation.",
    paste("Call:", paste(deparse(x$call), collapse = " "))
  )
  writeLines(manifest_lines, file.path(output_dir, "run_manifest.txt"), useBytes = TRUE)

  checksum_paths <- list.files(output_dir, full.names = TRUE)
  checksum_paths <- checksum_paths[
    file.info(checksum_paths)$isdir %in% FALSE &
      basename(checksum_paths) != "artifact_checksums.csv"
  ]
  artifact_checksums <- data.frame(
    File = basename(checksum_paths),
    MD5 = unname(tools::md5sum(checksum_paths)),
    stringsAsFactors = FALSE
  )
  artifact_checksums <- artifact_checksums[order(artifact_checksums$File), ]
  utils::write.csv(artifact_checksums,
    file.path(output_dir, "artifact_checksums.csv"), row.names = FALSE)
  invisible(output_dir)
}

#' Run the complete directory-based workflow
#'
#' @param data_dir,crop,harvest_month Passed to [read_crop_data()].
#' @param output_dir Optional artifact directory. `NULL` performs no writes.
#' @param config,last_yield_year,predict_through,verbose Passed to
#'   [compare_crop_models()].
#' @param overwrite Passed to [write_crop_results()].
#'
#' @return A `crop_model_comparison` object.
#' @export
run_crop_workflow <- function(
    data_dir, crop, harvest_month, output_dir = NULL,
    config = crop_model_config(), last_yield_year = NULL,
    predict_through = NULL, verbose = TRUE, overwrite = FALSE) {
  data <- read_crop_data(
    data_dir, crop, harvest_month,
    weather_variables = config$weather_variables
  )
  comparison <- compare_crop_models(
    data, config, last_yield_year, predict_through, verbose
  )
  if (!is.null(output_dir)) {
    write_crop_results(comparison, output_dir, overwrite = overwrite)
  }
  comparison
}
