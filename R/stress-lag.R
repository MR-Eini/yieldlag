cy_validate_stress_pair <- function(temperature, precipitation) {
  if (xor(is.null(temperature), is.null(precipitation))) {
    stop("Specify both stress temperature and precipitation variables, or neither.",
      call. = FALSE)
  }
  if (!is.null(temperature)) {
    valid <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
    if (!valid(temperature) || !valid(precipitation) || temperature == precipitation) {
      stop("Stress variables must be distinct, non-empty variable labels.", call. = FALSE)
    }
  }
}

cy_fit_stress_climatology <- function(data, manifest) {
  x <- as.matrix(data[, manifest$Term, drop = FALSE])
  regions <- sort(unique(as.character(data$RS)))
  centers <- do.call(rbind, lapply(regions, function(region) {
    colMeans(x[as.character(data$RS) == region, , drop = FALSE])
  }))
  dimnames(centers) <- list(regions, manifest$Term)
  residual <- x - centers[match(as.character(data$RS), regions), , drop = FALSE]
  scale <- sqrt(colSums(residual^2) / max(1L, nrow(x) - length(regions)))
  scale[!is.finite(scale) | scale < 1e-10] <- 1
  list(terms = manifest$Term, regions = regions, centers = centers,
    fallback_center = colMeans(x), scale = scale)
}

cy_stress_anomalies <- function(climatology, data) {
  x <- as.matrix(data[, climatology$terms, drop = FALSE])
  region_index <- match(as.character(data$RS), climatology$regions)
  centers <- matrix(climatology$fallback_center, nrow(data), ncol(x), byrow = TRUE)
  known <- !is.na(region_index)
  centers[known, ] <- climatology$centers[region_index[known], , drop = FALSE]
  sweep(x - centers, 2L, climatology$scale, "/")
}

cy_stress_basis <- function(data, manifest, climatology, threshold,
    temperature_variable = NULL, precipitation_variable = NULL) {
  z <- cy_stress_anomalies(climatology, data)
  features <- cbind(z, pmax(z - threshold, 0), pmax(-z - threshold, 0))
  blocks <- lapply(c("linear", "upper_tail", "lower_tail"), function(component) {
    part <- manifest
    part$SourceTerm <- part$Term
    part$Term <- paste(component, part$Term, sep = "__")
    part$Variable <- paste(component, part$Variable, sep = "__")
    part$Component <- component
    part
  })
  feature_manifest <- do.call(rbind, blocks)
  if (!is.null(temperature_variable)) {
    temperature <- manifest[manifest$Variable == temperature_variable, , drop = FALSE]
    precipitation <- manifest[manifest$Variable == precipitation_variable, , drop = FALSE]
    if (!nrow(temperature) || !nrow(precipitation)) {
      stop("Configured stress variables are absent from the weather manifest.", call. = FALSE)
    }
    if (anyDuplicated(temperature$CalendarMonth) || anyDuplicated(precipitation$CalendarMonth)) {
      stop("Compound stress requires one term per variable and calendar month.", call. = FALSE)
    }
    temperature <- temperature[order(temperature$AgriculturalPosition), , drop = FALSE]
    matched <- match(temperature$CalendarMonth, precipitation$CalendarMonth)
    if (anyNA(matched) || nrow(temperature) != nrow(precipitation) ||
        any(temperature$AgriculturalPosition != precipitation$AgriculturalPosition[matched])) {
      stop("Stress temperature and precipitation must have matching seasonal months.", call. = FALSE)
    }
    compound <- pmax(z[, temperature$Term, drop = FALSE] - threshold, 0) *
      pmax(-z[, precipitation$Term[matched], drop = FALSE] - threshold, 0)
    part <- temperature
    part$SourceTerm <- paste(temperature$Term, precipitation$Term[matched], sep = "*")
    part$Term <- paste0("compound_hot_dry__m", sprintf("%02d", part$CalendarMonth))
    part$Variable <- "compound_hot_dry"
    part$Component <- "compound_hot_dry"
    feature_manifest <- rbind(feature_manifest, part)
    features <- cbind(features, compound)
  }
  colnames(features) <- feature_manifest$Term
  panel <- data[, intersect(c("RS", "Year", ".yield"), names(data)), drop = FALSE]
  for (term in colnames(features)) panel[[term]] <- features[, term]
  rownames(feature_manifest) <- NULL
  list(panel = panel, manifest = feature_manifest)
}

cy_fit_stress_lag <- function(data, manifest, lambda = 100, smooth_ratio = 10,
    threshold = 0.75, temperature_variable = NULL, precipitation_variable = NULL,
    robust = TRUE) {
  if (is.null(lambda)) lambda <- 100
  if (is.null(smooth_ratio)) smooth_ratio <- 10
  if (is.null(threshold)) threshold <- 0.75
  scalar <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  if (!scalar(lambda) || lambda <= 0 || !scalar(smooth_ratio) || smooth_ratio < 0 ||
      !scalar(threshold) || threshold <= 0) {
    stop("stress_lag requires positive lambda and threshold, and non-negative smooth_ratio.",
      call. = FALSE)
  }
  cy_validate_stress_pair(temperature_variable, precipitation_variable)
  climatology <- cy_fit_stress_climatology(data, manifest)
  basis <- cy_stress_basis(data, manifest, climatology, threshold,
    temperature_variable, precipitation_variable)
  engine <- cy_fit_panel_ridge(data = basis$panel, manifest = basis$manifest,
    lambda = lambda, smooth_ratio = smooth_ratio, robust = robust)
  engine$method <- "stress_lag"
  engine$climatology <- climatology
  engine$source_manifest <- manifest
  engine$stress_feature_manifest <- basis$manifest
  engine$params <- list(lambda = lambda, smooth_ratio = smooth_ratio,
    threshold = threshold, temperature_variable = temperature_variable,
    precipitation_variable = precipitation_variable)
  engine
}

cy_stress_prediction_basis <- function(engine, data) {
  cy_stress_basis(data, engine$source_manifest, engine$climatology,
    engine$params$threshold, engine$params$temperature_variable,
    engine$params$precipitation_variable)
}

cy_predict_stress_lag <- function(engine, data, use_ar = TRUE) {
  basis <- cy_stress_prediction_basis(engine, data)
  cy_predict_panel_ridge(engine, basis$panel, use_ar)
}

#' Decompose a seasonal stress-lag prediction
#'
#' Reports additive contributions in the response unit. Contributions are
#' centered at training feature means and reproduce the model prediction.
#' They are statistical components, not causal effects or measured crop losses.
#'
#' @param object A `crop_yield_model` fitted with method `stress_lag`.
#' @param newdata Prediction panel or a `crop_yield_data` object.
#' @param use_ar Include the residual AR(1) correction.
#' @return A data frame with region/year, intercept, trend, regional effects,
#'   linear anomalies, upper/lower anomaly tails, compound hot-dry effects,
#'   residual correction, and their sum (`Prediction`).
#' @export
#' @examples
#' data <- synthetic_crop_example()
#' model <- fit_crop_model(data, "stress_lag", robust = FALSE)
#' explain_crop_prediction(model, subset(data$panel, Year == 2016))
explain_crop_prediction <- function(object, newdata, use_ar = TRUE) {
  if (!inherits(object, "crop_yield_model") || object$method != "stress_lag") {
    stop("Prediction decomposition currently supports stress_lag models.", call. = FALSE)
  }
  panel <- cy_prediction_panel(newdata, object$manifest)
  engine <- object$engine
  basis <- cy_stress_prediction_basis(engine, panel)
  transformed <- cy_transform(engine$preprocessor, basis$panel)
  regional <- cy_region_columns(panel$RS, transformed$year, engine$regions)
  weather <- sweep(transformed$x, 2L, engine$coef[colnames(transformed$x)], "*")
  component <- function(label) {
    terms <- engine$stress_feature_manifest$Term[
      engine$stress_feature_manifest$Component == label]
    rowSums(weather[, terms, drop = FALSE])
  }
  result <- data.frame(RS = panel$RS, Year = panel$Year,
    Intercept = rep(engine$intercept, nrow(panel)),
    Trend = transformed$year * engine$coef["year"],
    Regional = as.numeric(regional %*% engine$coef[colnames(regional)]),
    LinearAnomaly = component("linear"), UpperTail = component("upper_tail"),
    LowerTail = component("lower_tail"), HotDry = component("compound_hot_dry"),
    ARCorrection = if (isTRUE(use_ar)) cy_ar_correction(engine, panel) else rep(0, nrow(panel)))
  result$Prediction <- rowSums(result[, -(1:2), drop = FALSE])
  result
}

#' Diagnose weather support for a prediction
#'
#' Counts weather terms outside their observed training ranges and reports the
#' largest absolute standardized anomaly from the training mean. This diagnostic
#' is marginal: it does not establish support of joint weather combinations,
#' probability of error, or valid prediction interval coverage.
#'
#' @param object A fitted `crop_yield_model`, including an ensemble.
#' @param newdata Prediction panel or `crop_yield_data` object.
#' @return A data frame with region/year, `OutsideTerms`, `TotalTerms`,
#'   `MaxAbsZ`, and `UnseenRegion`. Ranges are pooled across training regions.
#' @export
#' @examples
#' data <- synthetic_crop_example()
#' model <- fit_crop_model(data, "trend")
#' prediction_support(model, subset(data$panel, Year == 2016))
prediction_support <- function(object, newdata) {
  if (!inherits(object, "crop_yield_model")) {
    stop("object must be a crop_yield_model.", call. = FALSE)
  }
  panel <- cy_prediction_panel(newdata, object$manifest)
  engine <- object$engine
  if (engine$method == "ensemble") engine <- engine$base_models[[1]]
  support <- engine$weather_support
  if (is.null(support)) stop("Training support is unavailable; refit this model.", call. = FALSE)
  x <- as.matrix(panel[, support$terms, drop = FALSE])
  outside <- sweep(x, 2L, support$minimum, "<") | sweep(x, 2L, support$maximum, ">")
  z <- sweep(sweep(x, 2L, support$center, "-"), 2L, support$scale, "/")
  data.frame(RS = panel$RS, Year = panel$Year,
    OutsideTerms = rowSums(outside), TotalTerms = rep(ncol(x), nrow(x)),
    MaxAbsZ = if (nrow(x)) apply(abs(z), 1L, max) else numeric(),
    UnseenRegion = !panel$RS %in% support$regions)
}

cy_stress_coefficients <- function(engine) {
  table <- engine$stress_feature_manifest
  table$Coefficient <- unname(engine$coef[table$Term])
  table$BasisCenter <- unname(engine$preprocessor$center[table$Term])
  table$BasisScale <- unname(engine$preprocessor$scale[table$Term])
  table
}
