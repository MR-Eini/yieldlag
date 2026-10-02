# Result compilation, coefficient extraction, plots, and text reports.

cy_compile_results <- function(results, areas, national_yields) {
  cv_predictions <- do.call(rbind, lapply(results, `[[`, "cv_predictions"))
  final_predictions <- do.call(rbind, lapply(results, `[[`, "final_predictions"))
  national_cv <- do.call(rbind, lapply(results, function(result) {
    cy_aggregate_national(result$cv_predictions, areas, national_yields)
  }))
  national_final <- do.call(rbind, lapply(results, function(result) {
    cy_aggregate_national(result$final_predictions, areas, national_yields)
  }))

  # Province errors are spatially correlated, so averaging provincial
  # intervals does not produce a calibrated national interval. Calibrate one
  # national half-width using the separate calibration forecasts when present,
  # otherwise the earlier tuning forecasts.
  national_cv$ProvinceAggregatedLower80 <- national_cv$Lower80Weighted
  national_cv$ProvinceAggregatedUpper80 <- national_cv$Upper80Weighted
  national_final$ProvinceAggregatedLower80 <- national_final$Lower80Weighted
  national_final$ProvinceAggregatedUpper80 <- national_final$Upper80Weighted
  national_cv$NationalHalfWidth80 <- NA_real_
  national_final$NationalHalfWidth80 <- NA_real_
  for (method in names(results)) {
    calibration_phase <- if (any(national_cv$Method == method &
        national_cv$Phase == "calibration")) "calibration" else "tuning"
    tuning_index <- national_cv$Method == method & national_cv$Phase == calibration_phase
    tuning_observed <- cy_national_observed(national_cv[tuning_index, , drop = FALSE])
    half_width <- cy_empirical_half_width(
      tuning_observed, national_cv$PredictedWeighted[tuning_index]
    )
    cv_index <- national_cv$Method == method
    final_index <- national_final$Method == method
    national_cv$NationalHalfWidth80[cv_index] <- half_width
    national_final$NationalHalfWidth80[final_index] <- half_width
    national_cv$Lower80Weighted[cv_index] <-
      national_cv$PredictedWeighted[cv_index] - half_width
    national_cv$Upper80Weighted[cv_index] <-
      national_cv$PredictedWeighted[cv_index] + half_width
    national_final$Lower80Weighted[final_index] <-
      national_final$PredictedWeighted[final_index] - half_width
    national_final$Upper80Weighted[final_index] <-
      national_final$PredictedWeighted[final_index] + half_width
  }

  metrics <- list()
  by_region <- list()
  by_year <- list()
  for (method in names(results)) {
    evaluation <- results[[method]]$evaluation_predictions
    province_metric <- cy_add_interval_metrics(
      cy_metrics(evaluation$Observed, evaluation$Predicted), evaluation
    )
    metrics[[paste(method, "province")]] <- data.frame(
      Method = method, Level = "Province-year", province_metric
    )

    national <- national_cv[
      national_cv$Method == method & national_cv$Phase == "evaluation",
      , drop = FALSE
    ]
    national_observed <- cy_national_observed(national)
    national_metric <- cy_metrics(national_observed, national$PredictedWeighted)
    national_metric$Coverage80 <- mean(
      national_observed >= national$Lower80Weighted &
        national_observed <= national$Upper80Weighted
    )
    national_metric$MeanWidth80 <- mean(
      national$Upper80Weighted - national$Lower80Weighted
    )
    metrics[[paste(method, "national")]] <- data.frame(
      Method = method, Level = "National", national_metric
    )

    by_region[[method]] <- do.call(rbind, lapply(sort(unique(evaluation$RS)), function(region) {
      part <- evaluation[evaluation$RS == region, ]
      data.frame(Method = method, RS = region, cy_metrics(part$Observed, part$Predicted))
    }))
    by_year[[method]] <- do.call(rbind, lapply(sort(unique(evaluation$Year)), function(year) {
      part <- evaluation[evaluation$Year == year, ]
      data.frame(Method = method, Year = year, cy_metrics(part$Observed, part$Predicted))
    }))
  }
  metrics <- do.call(rbind, metrics)
  rownames(metrics) <- NULL
  metrics$Rank <- ave(metrics$RMSE, metrics$Level, FUN = function(values) rank(values, ties.method = "min"))
  metrics <- metrics[order(metrics$Level, metrics$Rank, metrics$RMSE), ]
  list(
    metrics = metrics,
    by_region = do.call(rbind, by_region),
    by_year = do.call(rbind, by_year),
    cv_predictions = cv_predictions,
    final_predictions = final_predictions,
    national_cv = national_cv,
    national_final = national_final
  )
}

cy_extract_monthly_coefficients <- function(results, manifest) {
  output <- list()
  for (method in intersect(c("panel_ridge", "hierarchical"), names(results))) {
    model <- results[[method]]$final_model
    coefficients <- if (method == "panel_ridge") model$coef else model$global_coef
    part <- manifest
    part$Method <- method
    part$StandardizedEstimate <- as.numeric(coefficients[part$Term])
    scale <- model$preprocessor$scale[part$Term]
    part$OriginalScaleEstimate <- part$StandardizedEstimate / scale
    output[[method]] <- part
  }
  if (!length(output)) return(data.frame())
  do.call(rbind, output)
}

cy_write_markdown_report <- function(
    path, config, year_split, compiled, selected_parameters,
    ensemble_weights, runtime_seconds) {
  province <- compiled$metrics[compiled$metrics$Level == "Province-year", ]
  national <- compiled$metrics[compiled$metrics$Level == "National", ]
  best_province <- province[which.min(province$RMSE), ]
  best_national <- national[which.min(national$RMSE), ]
  lines <- c(
    "# Reference experiment report",
    "",
    paste("- Crop:", config$crop),
    paste("- Training cutoff:", config$last_yield_year),
    paste("- Tuning years:", paste(year_split$tuning, collapse = ", ")),
    paste("- Later evaluation years:", paste(year_split$evaluation, collapse = ", ")),
    paste("- Runtime (seconds):", round(runtime_seconds, 3)),
    "",
    "## Primary results",
    "",
    paste0(
      "Best province-year RMSE: **", round(best_province$RMSE, 3),
      " dt/ha** (", best_province$Method, ")."
    ),
    paste0(
      "Best national RMSE: **", round(best_national$RMSE, 3),
      " dt/ha** (", best_national$Method, ")."
    ),
    "",
    "The national evaluation contains only seven years; national rankings should be treated as provisional. Because this period has been inspected during framework development, new later data are required for confirmatory testing.",
    "",
    "## Evaluation metrics",
    "",
    "```",
    capture.output(print(compiled$metrics, row.names = FALSE)),
    "```",
    "",
    "## Selected model settings",
    "",
    "```",
    capture.output(print(selected_parameters, row.names = FALSE)),
    "```"
  )
  if (!is.null(ensemble_weights) && nrow(ensemble_weights)) {
    lines <- c(lines,
      "",
      "## Ensemble weights",
      "",
      "```",
      capture.output(print(ensemble_weights, row.names = FALSE)),
      "```"
    )
  }
  lines <- c(lines,
    "",
    "## Reproducibility note",
    "",
    "Every evaluation prediction uses only earlier years. Hyperparameters, ensemble weights, and prediction-interval width are selected on the earlier tuning period. The 2012-2018 block is a later development benchmark, not a permanently untouched confirmatory dataset."
  )
  writeLines(lines, path)
}

cy_plot_method_comparison <- function(metrics, path) {
  png(path, width = 1500, height = 850, res = 150)
  par(mfrow = c(1, 2), mar = c(7.5, 4.5, 3.5, 1), oma = c(0, 0, 3, 0))
  for (level in c("Province-year", "National")) {
    part <- metrics[metrics$Level == level, ]
    part <- part[order(part$RMSE), ]
    colors <- ifelse(
      part$Rank == 1, "#2F6B4F",
      ifelse(part$Method == "ensemble", "#D98E04", "#5B7FA3")
    )
    barplot(
      part$RMSE,
      names.arg = part$Method,
      las = 2,
      col = colors,
      border = NA,
      ylab = "RMSE (dt/ha)",
      main = level
    )
  }
  mtext("Later-period model comparison", side = 3, outer = TRUE, line = 0.6, cex = 1.2)
  dev.off()
}

cy_plot_national_predictions <- function(
    national_cv, national_final, path, last_yield_year, last_weather_year) {
  methods <- unique(national_cv$Method)
  palette <- c("#4C78A8", "#F58518", "#54A24B", "#B279A2", "#E45756", "#8C564B")
  colors <- setNames(rep(palette, length.out = length(methods)), methods)
  png(path, width = 1500, height = 900, res = 150)
  first_cv <- national_cv[national_cv$Method == methods[1], ]
  first_final <- national_final[
    national_final$Method == methods[1] & national_final$Year == last_weather_year,
  ]
  observed <- c(cy_national_observed(first_cv), cy_national_observed(first_final))
  years <- c(first_cv$Year, first_final$Year)
  forecast_values <- c(
    national_cv$PredictedWeighted,
    national_final$PredictedWeighted[national_final$Year == last_weather_year]
  )
  ranges <- range(c(observed, forecast_values), na.rm = TRUE)
  plot(years, observed, type = "o", pch = 19, col = "grey30",
    ylim = ranges, xlab = "Year", ylab = "Yield (dt/ha)",
    main = "Chronological national forecasts from raw monthly weather")
  for (method in methods) {
    part_cv <- national_cv[national_cv$Method == method, ]
    part_final <- national_final[
      national_final$Method == method & national_final$Year == last_weather_year,
    ]
    lines(
      c(part_cv$Year, part_final$Year),
      c(part_cv$PredictedWeighted, part_final$PredictedWeighted),
      col = colors[method], lwd = 1.8
    )
  }
  abline(v = last_yield_year + 0.5, lty = 2, col = "grey45")
  legend("topleft", c("Observed", methods),
    col = c("grey30", colors[methods]), lty = 1,
    pch = c(19, rep(NA, length(methods))), bty = "n", cex = 0.85)
  dev.off()
}

cy_plot_monthly_coefficients <- function(coefficients, path) {
  if (!nrow(coefficients)) return(invisible(NULL))
  methods <- unique(coefficients$Method)
  variables <- unique(coefficients$Variable)
  colors <- setNames(c("#4C78A8", "#E45756")[seq_along(methods)], methods)
  png(path, width = 1500, height = 1050, res = 150)
  par(mfrow = c(3, 3), mar = c(3.2, 3.8, 2.2, 0.8), oma = c(2, 1, 4, 1))
  for (variable in variables) {
    part <- coefficients[coefficients$Variable == variable, ]
    ylim <- range(part$StandardizedEstimate, na.rm = TRUE)
    first <- part[part$Method == methods[1], ]
    plot(first$AgriculturalPosition, first$StandardizedEstimate,
      type = "n", xlim = c(0.5, 12.5), ylim = ylim,
      xaxt = "n", xlab = "Month", ylab = "Coefficient", main = variable)
    axis(1, at = first$AgriculturalPosition,
      labels = sprintf("%02d", first$CalendarMonth), cex.axis = 0.75)
    abline(h = 0, col = "grey60", lty = 2)
    for (method in methods) {
      method_part <- part[part$Method == method, ]
      method_part <- method_part[order(method_part$AgriculturalPosition), ]
      lines(method_part$AgriculturalPosition, method_part$StandardizedEstimate,
        type = "b", pch = 19, col = colors[method], cex = 0.65)
    }
  }
  plot.new()
  legend("center", methods, col = colors[methods], lty = 1, pch = 19, bty = "n")
  plot.new()
  mtext("Global monthly weather coefficients", side = 3, outer = TRUE, line = 1.2, cex = 1.2)
  dev.off()
}
