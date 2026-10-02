# Shared numerical utilities for the crop-yield model repository.

cy_spd_solve <- function(a, b) {
  jitter <- 0
  for (attempt in seq_len(7L)) {
    candidate <- a
    if (jitter > 0) diag(candidate) <- diag(candidate) + jitter
    answer <- tryCatch({
      r <- chol(candidate)
      backsolve(r, forwardsolve(t(r), b))
    }, error = function(e) NULL)
    if (!is.null(answer)) return(as.numeric(answer))
    jitter <- if (jitter == 0) 1e-10 else jitter * 100
  }
  stop("Unable to solve penalized normal equations.", call. = FALSE)
}

cy_penalized_origin <- function(x, y, penalty_matrix, weights = NULL) {
  x <- as.matrix(x)
  y <- as.numeric(y)
  if (is.null(weights)) weights <- rep(1, length(y))
  sw <- sqrt(pmax(as.numeric(weights), 1e-8))
  a <- x * sw
  b <- y * sw
  cy_spd_solve(crossprod(a) + penalty_matrix, crossprod(a, b))
}

cy_penalized_intercept <- function(x, y, penalty_matrix, weights = NULL) {
  x <- as.matrix(x)
  y <- as.numeric(y)
  if (is.null(weights)) weights <- rep(1, length(y))
  weights <- pmax(as.numeric(weights), 1e-8)
  weight_sum <- sum(weights)
  y_mean <- sum(weights * y) / weight_sum
  x_mean <- colSums(x * weights) / weight_sum
  x_centered <- sweep(x, 2L, x_mean, "-")
  coef <- cy_penalized_origin(
    x_centered, y - y_mean, penalty_matrix, weights
  )
  list(intercept = y_mean - sum(x_mean * coef), coef = coef)
}

cy_impute_matrix <- function(data, feature_names, medians = NULL) {
  x <- as.matrix(data[, feature_names, drop = FALSE])
  storage.mode(x) <- "double"
  if (is.null(medians)) {
    medians <- apply(x, 2L, function(values) {
      value <- median(values, na.rm = TRUE)
      if (is.finite(value)) value else 0
    })
  }
  for (j in seq_len(ncol(x))) {
    missing <- !is.finite(x[, j])
    if (any(missing)) x[missing, j] <- medians[j]
  }
  list(x = x, medians = medians)
}

cy_fit_preprocessor <- function(data, feature_names) {
  imputed <- cy_impute_matrix(data, feature_names)
  scale <- apply(imputed$x, 2L, sd)
  scale[!is.finite(scale) | scale < 1e-10] <- 1
  year_scale <- sd(data$Year)
  if (!is.finite(year_scale) || year_scale < 1e-10) year_scale <- 1
  list(
    feature_names = feature_names,
    medians = imputed$medians,
    center = colMeans(imputed$x),
    scale = scale,
    year_center = mean(data$Year),
    year_scale = year_scale
  )
}

cy_transform <- function(preprocessor, data) {
  x <- cy_impute_matrix(
    data, preprocessor$feature_names, preprocessor$medians
  )$x
  x <- sweep(x, 2L, preprocessor$center, "-")
  x <- sweep(x, 2L, preprocessor$scale, "/")
  colnames(x) <- preprocessor$feature_names
  year <- (as.numeric(data$Year) - preprocessor$year_center) /
    preprocessor$year_scale
  list(x = x, year = year)
}

cy_make_weather_penalty <- function(
    term_names, manifest, lambda, smooth_ratio,
    year_factor = 0.05, region_factor = NULL) {
  factors <- rep(1, length(term_names))
  names(factors) <- term_names
  if ("year" %in% term_names) factors["year"] <- year_factor
  if (!is.null(region_factor)) {
    region_intercepts <- startsWith(term_names, "region_") &
      !startsWith(term_names, "region_year_")
    region_trends <- startsWith(term_names, "region_year_")
    factors[region_intercepts] <- region_factor[1]
    factors[region_trends] <- region_factor[2]
  }
  penalty <- diag(lambda * factors, nrow = length(term_names))
  dimnames(penalty) <- list(term_names, term_names)
  if (smooth_ratio <= 0) return(penalty)
  for (variable in unique(manifest$Variable)) {
    part <- manifest[manifest$Variable == variable, , drop = FALSE]
    part <- part[order(part$AgriculturalPosition), , drop = FALSE]
    index <- match(part$Term, term_names)
    index <- index[!is.na(index)]
    if (length(index) < 3L) next
    difference_matrix <- diff(diag(length(index)), differences = 2)
    penalty[index, index] <- penalty[index, index] +
      lambda * smooth_ratio * crossprod(difference_matrix)
  }
  penalty
}

cy_robust_weights <- function(residual, student_df = 4) {
  scale <- 1.4826 * median(abs(residual - median(residual)))
  if (!is.finite(scale) || scale < 1e-8) scale <- sqrt(mean(residual^2))
  scale <- max(scale, 1e-8)
  (student_df + 1) / (student_df + (residual / scale)^2)
}

cy_estimate_ar1 <- function(regions, years, residuals) {
  numerator <- 0
  denominator <- 0
  for (region in unique(regions)) {
    index <- which(regions == region)
    index <- index[order(years[index])]
    if (length(index) < 2L) next
    previous <- index[-length(index)]
    current <- index[-1L]
    consecutive <- years[current] == years[previous] + 1
    previous <- previous[consecutive]
    current <- current[consecutive]
    if (!length(current)) next
    numerator <- numerator + sum(residuals[current] * residuals[previous])
    denominator <- denominator + sum(residuals[previous]^2)
  }
  rho <- if (denominator > 0) numerator / denominator else 0
  max(-0.8, min(0.8, rho))
}

cy_ar_correction <- function(model, new_data) {
  correction <- numeric(nrow(new_data))
  if (is.null(model$rho) || abs(model$rho) < 1e-12) return(correction)
  history <- model$training_residuals
  for (i in seq_len(nrow(new_data))) {
    candidates <- history[
      history$RS == as.character(new_data$RS[i]) &
        history$Year < new_data$Year[i],
      , drop = FALSE
    ]
    if (!nrow(candidates)) next
    last <- candidates[which.max(candidates$Year), , drop = FALSE]
    gap <- as.integer(new_data$Year[i] - last$Year)
    correction[i] <- model$rho^gap * last$residual
  }
  correction
}

cy_region_columns <- function(regions, year, region_levels) {
  n <- length(regions)
  intercepts <- matrix(0, n, length(region_levels))
  trends <- matrix(0, n, length(region_levels))
  colnames(intercepts) <- paste0("region_", region_levels)
  colnames(trends) <- paste0("region_year_", region_levels)
  for (j in seq_along(region_levels)) {
    match_region <- as.character(regions) == region_levels[j]
    intercepts[match_region, j] <- 1
    trends[match_region, j] <- year[match_region]
  }
  cbind(intercepts, trends)
}

cy_project_simplex <- function(values) {
  sorted <- sort(values, decreasing = TRUE)
  cumulative <- cumsum(sorted)
  rho <- max(which(sorted - (cumulative - 1) / seq_along(sorted) > 0))
  theta <- (cumulative[rho] - 1) / rho
  pmax(values - theta, 0)
}

cy_fit_simplex_weights <- function(
    prediction_matrix, observed, shrinkage = 0,
    prior = rep(1 / ncol(prediction_matrix), ncol(prediction_matrix))) {
  x <- as.matrix(prediction_matrix)
  y <- as.numeric(observed)
  keep <- is.finite(y) & apply(x, 1L, function(row) all(is.finite(row)))
  x <- x[keep, , drop = FALSE]
  y <- y[keep]
  prior <- cy_project_simplex(as.numeric(prior))
  # The simplex makes each row mean irrelevant. Centering improves the
  # conditioning of the stacking optimization without changing predictions.
  row_center <- rowMeans(x)
  x_centered <- sweep(x, 1L, row_center, "-")
  y_centered <- y - row_center
  weights <- prior
  eigen_max <- max(eigen(
    crossprod(x_centered), symmetric = TRUE, only.values = TRUE
  )$values)
  lipschitz <- 2 * (eigen_max + shrinkage)
  step <- if (is.finite(lipschitz) && lipschitz > 0) 1 / lipschitz else 1e-4
  for (iteration in seq_len(10000L)) {
    gradient <- 2 * crossprod(
      x_centered, x_centered %*% weights - y_centered
    ) + 2 * shrinkage * (weights - prior)
    updated <- cy_project_simplex(weights - step * as.numeric(gradient))
    if (max(abs(updated - weights)) < 1e-10) {
      weights <- updated
      break
    }
    weights <- updated
  }
  setNames(weights, colnames(x))
}
