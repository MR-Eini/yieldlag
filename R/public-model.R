cy_default_parameters <- function(method, data) {
  switch(method,
    trend = list(),
    persistence = list(),
    panel_ridge = list(lambda = 100, smooth_ratio = 10),
    local_ridge = list(lambda = 100, smooth_ratio = 10),
    pcr = list(components = min(5L, nrow(data$manifest),
      max(1L, length(unique(data$panel$Year)) - 2L))),
    hierarchical = list(lambda_global = 100, lambda_region = 300, smooth_ratio = 10),
    stress_lag = list(lambda = 100, smooth_ratio = 10, threshold = 0.75),
    stop("fit_crop_model() fits base methods; use compare_crop_models() for an ensemble.",
      call. = FALSE)
  )
}

cy_as_public_model <- function(engine, manifest, parameters = list(),
    interval_level = 0.80, interval_half_width = NA_real_, crop = NA_character_) {
  structure(list(
    method = engine$method,
    engine = engine,
    manifest = manifest,
    parameters = parameters,
    crop = crop,
    training_years = engine$training_years,
    interval_level = interval_level,
    interval_half_width = interval_half_width
  ), class = "crop_yield_model")
}

#' Fit one statistical crop-yield model
#'
#' This is the direct fitting interface. It does not tune parameters and does
#' not estimate a prediction interval, which prevents accidental claims that
#' an in-sample fit has been validated. Use [compare_crop_models()] for
#' rolling-origin tuning, interval calibration, and later evaluation.
#'
#' @param data A [prepare_crop_data()] or [read_crop_data()] result.
#' @param method One base method. Ensembles require the comparison workflow.
#' @param parameters Named list of method parameters. `NULL` uses documented,
#'   fixed defaults rather than selecting them from the supplied response.
#'   For `stress_lag`, parameters are `lambda`, `smooth_ratio`, `threshold`,
#'   and optional `temperature_variable`/`precipitation_variable` labels.
#'   Defaults are 100, 10, and 0.75, with compound terms disabled.
#'   Optional `components` selects a subset of `linear`, `upper_tail`,
#'   `lower_tail`, and `compound_hot_dry`; `linear` is required.
#'   `regional_effects = FALSE` removes regional intercept/trend deviations
#'   for a controlled ablation. Defaults retain all components and deviations.
#' @param robust Whether to use robust fitting where supported.
#'
#' @return A `crop_yield_model` object.
#' @export
#' @examples
#' wheat <- read_crop_data(poland_example_path(), "wheat", 7)
#' trend <- fit_crop_model(wheat, method = "trend")
#' predict(trend, wheat$panel[1:3, ])
fit_crop_model <- function(data, method = "hierarchical", parameters = NULL, robust = TRUE) {
  if (!inherits(data, "crop_yield_data")) {
    stop("data must be created by prepare_crop_data() or read_crop_data().", call. = FALSE)
  }
  method <- match.arg(method, cy_base_methods())
  training <- data$panel[is.finite(data$panel$.yield), , drop = FALSE]
  if (length(unique(training$Year)) < 5L) {
    stop("At least five observed years are required to fit a model.", call. = FALSE)
  }
  if (is.null(parameters)) parameters <- cy_default_parameters(method, data)
  engine <- cy_fit_model(method, training, data$manifest, parameters, robust = robust)
  cy_as_public_model(engine, data$manifest, parameters, crop = data$crop)
}

cy_prediction_panel <- function(newdata, manifest) {
  if (inherits(newdata, "crop_yield_data")) newdata <- newdata$panel
  newdata <- as.data.frame(newdata, stringsAsFactors = FALSE)
  required <- c("RS", "Year", manifest$Term)
  missing <- setdiff(required, names(newdata))
  if (length(missing)) {
    stop("newdata is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  newdata$RS <- as.character(newdata$RS)
  newdata$Year <- as.integer(newdata$Year)
  for (term in manifest$Term) newdata[[term]] <- as.numeric(newdata[[term]])
  if (any(!is.finite(as.matrix(newdata[, manifest$Term, drop = FALSE])))) {
    stop("newdata weather terms must be finite.", call. = FALSE)
  }
  newdata
}

#' Predict crop yields from a fitted model
#'
#' @param object A `crop_yield_model` object.
#' @param newdata A data frame with `RS`, `Year`, and every weather term used by
#'   the model, or a `crop_yield_data` object.
#' @param interval Either `"none"` or `"prediction"`. Prediction intervals are
#'   available only for models extracted from [compare_crop_models()].
#' @param use_ar Whether to apply the pooled residual AR(1) correction.
#' @param ... Unused.
#'
#' @return A numeric vector, or a data frame with `fit`, `lower`, and `upper`.
#' @export
predict.crop_yield_model <- function(
    object, newdata, interval = c("none", "prediction"), use_ar = TRUE, ...) {
  interval <- match.arg(interval)
  panel <- cy_prediction_panel(newdata, object$manifest)
  regional_engines <- if (object$engine$method == "ensemble") {
    Filter(
      function(engine) engine$method %in% c("trend", "persistence", "local_ridge"),
      object$engine$base_models
    )
  } else if (object$engine$method %in% c("trend", "persistence", "local_ridge")) {
    list(object$engine)
  } else list()
  if (length(regional_engines)) {
    supported <- Reduce(intersect, lapply(regional_engines, `[[`, "regions"))
    unknown <- setdiff(unique(panel$RS), supported)
    if (length(unknown)) {
      stop(
        object$engine$method, " contains regional components and cannot predict regions absent from training: ",
        paste(unknown, collapse = ", "), call. = FALSE
      )
    }
  }
  fit <- cy_predict_model(object$engine, panel, use_ar = use_ar)
  if (interval == "none") return(as.numeric(fit))
  half_width <- object$interval_half_width
  if (!is.finite(half_width)) {
    stop("This model has no calibrated interval; extract a model from compare_crop_models().",
      call. = FALSE)
  }
  data.frame(
    fit = as.numeric(fit),
    lower = as.numeric(fit) - half_width,
    upper = as.numeric(fit) + half_width
  )
}

#' @export
print.crop_yield_model <- function(x, ...) {
  cat("<crop_yield_model>\n")
  cat("  method: ", x$method, "\n", sep = "")
  cat("  crop: ", ifelse(is.na(x$crop), "unspecified", x$crop), "\n", sep = "")
  cat("  training years: ", paste(x$training_years, collapse = "-"), "\n", sep = "")
  cat("  parameters: ", cy_params_string(x$parameters), "\n", sep = "")
  cat("  residual AR(1): ", round(x$engine$rho, 3), "\n", sep = "")
  if (is.finite(x$interval_half_width)) {
    cat("  calibrated interval: ", 100 * x$interval_level,
        "% +/-", round(x$interval_half_width, 3), "\n", sep = "")
  }
  invisible(x)
}

#' @export
coef.crop_yield_model <- function(object, ...) {
  engine <- object$engine
  switch(engine$method,
    trend = engine$coefficients,
    persistence = engine$history,
    panel_ridge = c(`(Intercept)` = engine$intercept, engine$coef),
    stress_lag = c(`(Intercept)` = engine$intercept, engine$coef),
    local_ridge = list(intercepts = engine$intercepts, coefficients = engine$coefficients),
    pcr = c(`(Intercept)` = engine$intercept, engine$coef),
    hierarchical = list(
      global = c(`(Intercept)` = engine$global_intercept, engine$global_coef),
      regional_deviations = engine$regional_coef
    ),
    ensemble = engine$weights
  )
}

#' Calculate transparent predictive metrics
#'
#' @param observed,predicted Numeric vectors.
#' @param lower,upper Optional predictive interval bounds.
#'
#' @return A one-row data frame containing sample size, RMSE, MAE, bias,
#'   predictive R-squared, and squared correlation. Interval coverage and width
#'   are included when both bounds are supplied.
#' @export
#' @examples
#' yield_metrics(c(3, 4, 5), c(2.8, 4.1, 5.2))
yield_metrics <- function(observed, predicted, lower = NULL, upper = NULL) {
  result <- cy_metrics(observed, predicted)
  if (xor(is.null(lower), is.null(upper))) {
    stop("lower and upper must be supplied together.", call. = FALSE)
  }
  if (!is.null(lower)) {
    if (length(lower) != length(observed) || length(upper) != length(observed)) {
      stop("Interval bounds must have the same length as observed.", call. = FALSE)
    }
    frame <- data.frame(Observed = observed, Lower80 = lower, Upper80 = upper)
    result <- cy_add_interval_metrics(result, frame)
  }
  result
}
