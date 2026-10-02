cy_require_crop_data <- function(data) {
  if (!inherits(data, "crop_yield_data")) {
    stop("data must be created by prepare_crop_data() or read_crop_data().", call. = FALSE)
  }
}

cy_tuning_method_metrics <- function(results) {
  output <- lapply(results, function(result) {
    prediction <- result$tuning_predictions
    data.frame(Method = result$method,
      cy_metrics(prediction$Observed, prediction$Predicted),
      stringsAsFactors = FALSE)
  })
  table <- do.call(rbind, output)
  rownames(table) <- NULL
  table$Rank <- rank(table$RMSE, ties.method = "min")
  table[order(table$Rank, table$RMSE, table$MAE), , drop = FALSE]
}

#' Compare crop-yield methods with chronological validation
#'
#' Hyperparameters are learned from tuning years. Interval widths use a separate
#' calibration block when configured, otherwise tuning errors. Each prediction is rolling-origin: the
#' response for year `t` is predicted using response data strictly before `t`.
#' The package's automatic method is selected by tuning RMSE, never by the
#' later evaluation scores.
#'
#' @param data A `crop_yield_data` object.
#' @param config A [crop_model_config()] object.
#' @param last_yield_year Final observed year allowed in model development.
#'   Defaults to the latest finite response year.
#' @param predict_through Final weather year for final fitted predictions.
#'   Defaults to the latest year in the panel.
#' @param verbose Print progress messages.
#'
#' @return An auditable `crop_model_comparison` object containing candidate
#'   grids, selected hyperparameters, row-level predictions, metrics, splits,
#'   final fitted models, and input provenance.
#' @export
#' @examples
#' wheat <- read_crop_data(poland_example_path(), "wheat", 7)
#' # A full six-method comparison is intentionally not run during package checks.
#' \donttest{
#' comparison <- compare_crop_models(
#'   wheat,
#'   crop_model_config(methods = c("trend", "hierarchical")),
#'   last_yield_year = 2018,
#'   predict_through = 2019,
#'   verbose = FALSE
#' )
#' comparison
#' }
compare_crop_models <- function(
    data, config = crop_model_config(), last_yield_year = NULL,
    predict_through = NULL, verbose = TRUE) {
  cy_require_crop_data(data)
  if (!inherits(config, "crop_model_config")) {
    stop("config must be created by crop_model_config().", call. = FALSE)
  }
  observed_years <- sort(unique(data$panel$Year[is.finite(data$panel$.yield)]))
  if (!length(observed_years)) stop("No finite yield observations were found.", call. = FALSE)
  if (is.null(last_yield_year)) last_yield_year <- max(observed_years)
  if (is.null(predict_through)) predict_through <- max(data$panel$Year)
  last_yield_year <- as.integer(last_yield_year)
  predict_through <- as.integer(predict_through)
  if (length(last_yield_year) != 1L || is.na(last_yield_year) ||
      length(predict_through) != 1L || is.na(predict_through)) {
    stop("Year cutoffs must be single finite integers.", call. = FALSE)
  }
  if (predict_through < last_yield_year) {
    stop("predict_through cannot precede last_yield_year.", call. = FALSE)
  }
  training <- data$panel[
    data$panel$Year <= last_yield_year & is.finite(data$panel$.yield), , drop = FALSE
  ]
  years <- sort(unique(training$Year))
  if (!last_yield_year %in% years) {
    stop("No observed yields exist in last_yield_year.", call. = FALSE)
  }
  if (length(years) < 12L) {
    stop("At least 12 observed years are required for initial, tuning, and evaluation blocks.",
      call. = FALSE)
  }
  prediction_panel <- data$panel[
    data$panel$Year >= min(years) & data$panel$Year <= predict_through, , drop = FALSE
  ]
  if (!nrow(prediction_panel) || max(prediction_panel$Year) < predict_through) {
    stop("The weather panel does not reach predict_through.", call. = FALSE)
  }
  split <- cy_split_years(
    training$Year, config$initial_fraction, config$tuning_fraction,
    if (is.null(config$calibration_years)) 0L else config$calibration_years
  )
  if (length(split$evaluation) < 2L) {
    stop("The configured split leaves fewer than two evaluation years.", call. = FALSE)
  }
  methods <- config$methods
  base_methods <- setdiff(methods, "ensemble")
  if ("ensemble" %in% methods && !length(base_methods)) base_methods <- cy_base_methods()
  if ("ensemble" %in% methods && length(base_methods) < 2L) {
    stop("An ensemble requires at least two base methods.", call. = FALSE)
  }
  start_time <- proc.time()[["elapsed"]]
  if (isTRUE(verbose)) {
    message("Crop: ", data$crop)
    message("Observed training years: ", min(years), "-", max(years))
    message("Tuning: ", paste(split$tuning, collapse = ", "),
      "; evaluation: ", paste(split$evaluation, collapse = ", "))
  }
  internal_config <- unclass(config)
  results <- setNames(vector("list", length(base_methods)), base_methods)
  for (method in base_methods) {
    results[[method]] <- cy_run_base_method(
      method, training, data$manifest, split, prediction_panel,
      internal_config, verbose = isTRUE(verbose)
    )
  }
  if ("ensemble" %in% methods) {
    if (isTRUE(verbose)) message("Learning ensemble from tuning predictions")
    results$ensemble <- cy_build_ensemble(results, internal_config)
  }
  compiled <- cy_compile_results(results, data$areas, data$national_yields)
  tuning_metrics <- cy_tuning_method_metrics(results)
  selected_method <- tuning_metrics$Method[1]
  compiled$metrics$SelectedByTuning <- compiled$metrics$Method == selected_method
  runtime <- proc.time()[["elapsed"]] - start_time
  structure(list(
    call = match.call(),
    package_version = as.character(utils::packageVersion("yieldlag")),
    crop = data$crop,
    harvest_month = data$harvest_month,
    config = config,
    last_yield_year = last_yield_year,
    predict_through = predict_through,
    year_split = split,
    selected_method = selected_method,
    selection_rule = "minimum province-year tuning RMSE",
    tuning_method_metrics = tuning_metrics,
    results = results,
    metrics = compiled$metrics,
    metrics_by_region = compiled$by_region,
    metrics_by_year = compiled$by_year,
    province_cv_predictions = compiled$cv_predictions,
    national_cv_predictions = compiled$national_cv,
    province_predictions = compiled$final_predictions,
    national_predictions = compiled$national_final,
    monthly_coefficients = cy_extract_monthly_coefficients(results, data$manifest),
    manifest = data$manifest,
    prediction_panel = prediction_panel,
    areas = data$areas,
    national_yields = data$national_yields,
    provenance = data$provenance,
    aggregation = data$aggregation,
    runtime_seconds = unname(runtime)
  ), class = "crop_model_comparison")
}

#' Extract a final fitted model from a comparison
#'
#' @param x A `crop_model_comparison`.
#' @param method Method to extract. `NULL` uses the method selected on tuning
#'   RMSE only.
#'
#' @return A `crop_yield_model` with its empirically calibrated interval.
#' @export
get_crop_model <- function(x, method = NULL) {
  if (!inherits(x, "crop_model_comparison")) {
    stop("x must be a crop_model_comparison.", call. = FALSE)
  }
  if (is.null(method)) method <- x$selected_method
  if (length(method) != 1L || !method %in% names(x$results)) {
    stop("method was not fitted in this comparison.", call. = FALSE)
  }
  result <- x$results[[method]]
  cy_as_public_model(
    result$final_model, x$manifest, result$selected_params,
    interval_level = x$config$interval_level,
    interval_half_width = result$interval_half_width_80,
    crop = x$crop
  )
}

#' @export
print.crop_model_comparison <- function(x, ...) {
  cat("<crop_model_comparison>\n")
  cat("  crop: ", ifelse(is.na(x$crop), "unspecified", x$crop), "\n", sep = "")
  cat("  tuning years: ", paste(x$year_split$tuning, collapse = ", "), "\n", sep = "")
  cat("  evaluation years: ", paste(x$year_split$evaluation, collapse = ", "), "\n", sep = "")
  cat("  method selected using tuning only: ", x$selected_method, "\n", sep = "")
  selected <- x$metrics[
    x$metrics$Method == x$selected_method & x$metrics$Level == "Province-year", , drop = FALSE
  ]
  cat("  selected-method later RMSE: ", round(selected$RMSE, 3), "\n", sep = "")
  cat("  runtime: ", round(x$runtime_seconds, 2), " seconds\n", sep = "")
  invisible(x)
}

#' @export
summary.crop_model_comparison <- function(object, ...) {
  list(
    crop = object$crop,
    split = object$year_split,
    selection_rule = object$selection_rule,
    selected_method = object$selected_method,
    tuning_metrics = object$tuning_method_metrics,
    evaluation_metrics = object$metrics,
    runtime_seconds = object$runtime_seconds
  )
}

#' Plot a method comparison
#'
#' @param x A `crop_model_comparison` object.
#' @param level Either province-year or national evaluation.
#' @param metric One numeric column in `x$metrics`.
#' @param ... Additional arguments passed to [graphics::barplot()].
#'
#' @return The bar midpoints, invisibly.
#' @export
plot.crop_model_comparison <- function(
    x, level = c("Province-year", "National"), metric = "RMSE", ...) {
  level <- match.arg(level)
  if (!metric %in% names(x$metrics) || !is.numeric(x$metrics[[metric]])) {
    stop("metric must name a numeric evaluation metric.", call. = FALSE)
  }
  part <- x$metrics[x$metrics$Level == level, , drop = FALSE]
  part <- part[order(part[[metric]]), , drop = FALSE]
  colors <- ifelse(part$Method == x$selected_method, "#D98E04", "#4C78A8")
  midpoint <- graphics::barplot(
    part[[metric]], names.arg = part$Method, las = 2, col = colors,
    border = NA, ylab = metric, main = paste(level, "later evaluation"), ...
  )
  invisible(midpoint)
}
