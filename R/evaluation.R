# Chronological tuning, evaluation, and ensemble construction.

cy_params_string <- function(params) {
  if (!length(params)) return("none")
  values <- vapply(params, function(x) paste(x, collapse = ","), character(1))
  paste(paste(names(params), values, sep = "="), collapse = ";")
}

cy_empirical_half_width <- function(observed, predicted, level = 0.80) {
  errors <- abs(as.numeric(observed) - as.numeric(predicted))
  errors <- errors[is.finite(errors)]
  if (!length(errors)) return(NA_real_)
  as.numeric(quantile(errors, probs = level, names = FALSE, type = 8))
}

cy_rolling_method <- function(
    data, manifest, validation_years, method, params,
    robust = FALSE, verbose = FALSE) {
  output <- list()
  for (validation_year in validation_years) {
    train <- data[data$Year < validation_year & is.finite(data$.yield), , drop = FALSE]
    test <- data[data$Year == validation_year & is.finite(data$.yield), , drop = FALSE]
    if (!nrow(test) || length(unique(train$Year)) < 5L) next
    if (verbose) {
      message("    ", method, ": ", validation_year, " after ", max(train$Year))
    }
    model <- cy_fit_model(method, train, manifest, params, robust)
    output[[as.character(validation_year)]] <- data.frame(
      Method = method,
      RS = as.character(test$RS),
      Year = test$Year,
      Observed = test$.yield,
      Predicted = cy_predict_model(model, test, use_ar = TRUE),
      stringsAsFactors = FALSE
    )
  }
  if (!length(output)) return(data.frame())
  do.call(rbind, output)
}

cy_tune_method <- function(data, manifest, tuning_years, method, config, verbose = TRUE) {
  parameter_sets <- cy_parameter_sets(method, config)
  candidates <- vector("list", length(parameter_sets))
  for (i in seq_along(parameter_sets)) {
    if (verbose) {
      message(
        "  ", method, " tuning ", i, "/", length(parameter_sets),
        " [", cy_params_string(parameter_sets[[i]]), "]"
      )
    }
    prediction <- cy_rolling_method(
      data, manifest, tuning_years, method, parameter_sets[[i]],
      # Hyperparameters must be selected with the same robust estimator used
      # for evaluation and final fitting. Otherwise the tuning objective and
      # deployed model are different statistical procedures.
      robust = isTRUE(config$robust), verbose = FALSE
    )
    candidates[[i]] <- cbind(
      data.frame(
        Method = method,
        ParameterSet = i,
        Parameters = cy_params_string(parameter_sets[[i]]),
        stringsAsFactors = FALSE
      ),
      cy_metrics(prediction$Observed, prediction$Predicted)
    )
  }
  table <- do.call(rbind, candidates)
  table <- table[order(table$RMSE, table$MAE), , drop = FALSE]
  rownames(table) <- NULL
  selected_index <- table$ParameterSet[1]
  list(
    selected = parameter_sets[[selected_index]],
    table = table,
    selected_index = selected_index
  )
}

cy_run_base_method <- function(
    method, data, manifest, year_split, prediction_panel,
    config, verbose = TRUE) {
  if (verbose) message("Selecting ", method)
  tuning <- cy_tune_method(
    data, manifest, year_split$tuning, method, config, verbose
  )
  params <- tuning$selected
  if (verbose) message("  selected ", method, ": ", cy_params_string(params))

  tuning_prediction <- cy_rolling_method(
    data, manifest, year_split$tuning, method, params,
    robust = isTRUE(config$robust), verbose = FALSE
  )
  calibration_prediction <- if (length(year_split$calibration)) cy_rolling_method(
    data, manifest, year_split$calibration, method, params,
    robust = isTRUE(config$robust), verbose = FALSE
  ) else tuning_prediction[FALSE, , drop = FALSE]
  calibration <- if (nrow(calibration_prediction)) calibration_prediction else tuning_prediction
  predictive_sigma <- sqrt(mean(
    (calibration$Predicted - calibration$Observed)^2,
    na.rm = TRUE
  ))
  interval_half_width <- cy_empirical_half_width(
    calibration$Observed, calibration$Predicted,
    level = config$interval_level
  )
  tuning_prediction$Lower80 <- tuning_prediction$Predicted - interval_half_width
  tuning_prediction$Upper80 <- tuning_prediction$Predicted + interval_half_width
  tuning_prediction$Phase <- "tuning"
  calibration_prediction$Lower80 <- calibration_prediction$Predicted - interval_half_width
  calibration_prediction$Upper80 <- calibration_prediction$Predicted + interval_half_width
  calibration_prediction$Phase <- rep("calibration", nrow(calibration_prediction))

  if (verbose) message("  evaluating ", method)
  evaluation_prediction <- cy_rolling_method(
    data, manifest, year_split$evaluation, method, params,
    robust = isTRUE(config$robust), verbose = FALSE
  )
  evaluation_prediction$Lower80 <- evaluation_prediction$Predicted - interval_half_width
  evaluation_prediction$Upper80 <- evaluation_prediction$Predicted + interval_half_width
  evaluation_prediction$Phase <- "evaluation"

  final_model <- cy_fit_model(method, data, manifest, params, robust = isTRUE(config$robust))
  final_model$predictive_sigma <- predictive_sigma
  final_model$interval_half_width_80 <- interval_half_width
  final_prediction <- data.frame(
    Method = method,
    RS = as.character(prediction_panel$RS),
    Year = prediction_panel$Year,
    Observed = prediction_panel$.yield,
    StructuralMean = cy_predict_model(final_model, prediction_panel, use_ar = FALSE),
    Predicted = cy_predict_model(final_model, prediction_panel, use_ar = TRUE),
    Phase = "final",
    stringsAsFactors = FALSE
  )
  final_prediction$Lower80 <- final_prediction$Predicted - interval_half_width
  final_prediction$Upper80 <- final_prediction$Predicted + interval_half_width

  list(
    method = method,
    selected_params = params,
    tuning_table = tuning$table,
    tuning_predictions = tuning_prediction,
    calibration_predictions = calibration_prediction,
    evaluation_predictions = evaluation_prediction,
    cv_predictions = rbind(tuning_prediction, calibration_prediction, evaluation_prediction),
    predictive_sigma = predictive_sigma,
    interval_half_width_80 = interval_half_width,
    final_model = final_model,
    final_predictions = final_prediction
  )
}

cy_aligned_prediction_matrix <- function(results, slot) {
  first <- results[[1]][[slot]]
  key <- paste(first$RS, first$Year, sep = "_")
  matrix <- matrix(NA_real_, nrow(first), length(results),
    dimnames = list(NULL, names(results)))
  for (j in seq_along(results)) {
    part <- results[[j]][[slot]]
    part_key <- paste(part$RS, part$Year, sep = "_")
    matrix[, j] <- part$Predicted[match(key, part_key)]
  }
  list(
    keys = first[, intersect(c("RS", "Year", "Observed", "Phase"), names(first)), drop = FALSE],
    matrix = matrix
  )
}

cy_build_ensemble <- function(base_results, config) {
  tuning <- cy_aligned_prediction_matrix(base_results, "tuning_predictions")
  shrinkage_grid <- config$grids$ensemble$shrinkage
  prior <- rep(1 / ncol(tuning$matrix), ncol(tuning$matrix))
  candidates <- vector("list", length(shrinkage_grid))
  candidate_predictions <- vector("list", length(shrinkage_grid))
  years <- sort(unique(tuning$keys$Year))
  for (j in seq_along(shrinkage_grid)) {
    predicted <- rep(NA_real_, nrow(tuning$matrix))
    for (year in years) {
      holdout <- tuning$keys$Year == year
      fold_weights <- cy_fit_simplex_weights(
        tuning$matrix[!holdout, , drop = FALSE],
        tuning$keys$Observed[!holdout],
        shrinkage = shrinkage_grid[j], prior = prior
      )
      predicted[holdout] <- as.numeric(
        tuning$matrix[holdout, , drop = FALSE] %*% fold_weights
      )
    }
    candidate_predictions[[j]] <- predicted
    candidates[[j]] <- data.frame(
      Method = "ensemble",
      ParameterSet = j,
      Parameters = paste0("shrinkage=", shrinkage_grid[j]),
      cy_metrics(tuning$keys$Observed, predicted),
      stringsAsFactors = FALSE
    )
  }
  tuning_table <- do.call(rbind, candidates)
  tuning_table <- tuning_table[order(tuning_table$RMSE, tuning_table$MAE), , drop = FALSE]
  rownames(tuning_table) <- NULL
  selected_index <- tuning_table$ParameterSet[1]
  selected_shrinkage <- shrinkage_grid[selected_index]
  tuning_predicted <- candidate_predictions[[selected_index]]
  weights <- cy_fit_simplex_weights(
    tuning$matrix, tuning$keys$Observed,
    shrinkage = selected_shrinkage, prior = prior
  )
  calibration <- cy_aligned_prediction_matrix(base_results, "calibration_predictions")
  calibration_predicted <- as.numeric(calibration$matrix %*% weights)
  interval_observed <- if (length(calibration_predicted)) calibration$keys$Observed else tuning$keys$Observed
  interval_predicted <- if (length(calibration_predicted)) calibration_predicted else tuning_predicted
  predictive_sigma <- sqrt(mean((interval_predicted - interval_observed)^2))
  interval_half_width <- cy_empirical_half_width(
    interval_observed, interval_predicted,
    level = config$interval_level
  )
  tuning_output <- data.frame(
    Method = "ensemble",
    RS = tuning$keys$RS,
    Year = tuning$keys$Year,
    Observed = tuning$keys$Observed,
    Predicted = tuning_predicted,
    Lower80 = tuning_predicted - interval_half_width,
    Upper80 = tuning_predicted + interval_half_width,
    Phase = "tuning",
    stringsAsFactors = FALSE
  )
  calibration_output <- data.frame(Method = rep("ensemble", length(calibration_predicted)),
    RS = calibration$keys$RS, Year = calibration$keys$Year,
    Observed = calibration$keys$Observed, Predicted = calibration_predicted,
    Lower80 = calibration_predicted - interval_half_width,
    Upper80 = calibration_predicted + interval_half_width,
    Phase = rep("calibration", length(calibration_predicted)), stringsAsFactors = FALSE)

  evaluation <- cy_aligned_prediction_matrix(base_results, "evaluation_predictions")
  evaluation_predicted <- as.numeric(evaluation$matrix %*% weights)
  evaluation_output <- data.frame(
    Method = "ensemble",
    RS = evaluation$keys$RS,
    Year = evaluation$keys$Year,
    Observed = evaluation$keys$Observed,
    Predicted = evaluation_predicted,
    Lower80 = evaluation_predicted - interval_half_width,
    Upper80 = evaluation_predicted + interval_half_width,
    Phase = "evaluation",
    stringsAsFactors = FALSE
  )

  final <- cy_aligned_prediction_matrix(base_results, "final_predictions")
  final_predicted <- as.numeric(final$matrix %*% weights)
  structural_matrix <- sapply(base_results, function(result) result$final_predictions$StructuralMean)
  structural_mean <- as.numeric(structural_matrix %*% weights)
  final_output <- data.frame(
    Method = "ensemble",
    RS = final$keys$RS,
    Year = final$keys$Year,
    Observed = final$keys$Observed,
    StructuralMean = structural_mean,
    Predicted = final_predicted,
    Phase = "final",
    Lower80 = final_predicted - interval_half_width,
    Upper80 = final_predicted + interval_half_width,
    stringsAsFactors = FALSE
  )

  list(
    method = "ensemble",
    selected_params = c(list(shrinkage = selected_shrinkage), as.list(weights)),
    tuning_table = tuning_table,
    tuning_predictions = tuning_output,
    calibration_predictions = calibration_output,
    evaluation_predictions = evaluation_output,
    cv_predictions = rbind(tuning_output, calibration_output, evaluation_output),
    predictive_sigma = predictive_sigma,
    interval_half_width_80 = interval_half_width,
    final_model = structure(list(
      method = "ensemble",
      weights = weights,
      shrinkage = selected_shrinkage,
      base_models = lapply(base_results, `[[`, "final_model"),
      predictive_sigma = predictive_sigma,
      interval_half_width_80 = interval_half_width
    ), class = "cy_ensemble"),
    final_predictions = final_output,
    weights = weights
  )
}
