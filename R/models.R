# Selectable crop-yield model implementations sharing one interface.

cy_fit_trend <- function(data) {
  data <- data[is.finite(data$.yield), , drop = FALSE]
  regions <- sort(unique(as.character(data$RS)))
  coefficients <- matrix(NA_real_, nrow = length(regions), ncol = 2L,
    dimnames = list(regions, c("intercept", "year")))
  fitted <- numeric(nrow(data))
  for (region in regions) {
    index <- which(as.character(data$RS) == region)
    fit <- lm(.yield ~ Year, data = data[index, , drop = FALSE])
    coefficients[region, ] <- coef(fit)
    fitted[index] <- predict(fit)
  }
  residual <- data$.yield - fitted
  structure(list(
    method = "trend",
    coefficients = coefficients,
    regions = regions,
    rho = cy_estimate_ar1(as.character(data$RS), data$Year, residual),
    training_residuals = data.frame(RS = as.character(data$RS), Year = data$Year, residual),
    residual_sigma = sqrt(mean(residual^2)),
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_trend <- function(model, new_data, use_ar = TRUE) {
  prediction <- numeric(nrow(new_data))
  for (region in unique(as.character(new_data$RS))) {
    index <- which(as.character(new_data$RS) == region)
    if (!region %in% rownames(model$coefficients)) {
      prediction[index] <- mean(model$training_residuals$residual)
    } else {
      prediction[index] <- model$coefficients[region, "intercept"] +
        model$coefficients[region, "year"] * new_data$Year[index]
    }
  }
  if (use_ar) prediction <- prediction + cy_ar_correction(model, new_data)
  prediction
}

cy_fit_persistence <- function(data) {
  data <- data[is.finite(data$.yield), , drop = FALSE]
  data <- data[order(data$RS, data$Year), , drop = FALSE]
  regions <- sort(unique(as.character(data$RS)))
  residual_rows <- list()
  for (region in regions) {
    part <- data[as.character(data$RS) == region, c("RS", "Year", ".yield")]
    part <- part[order(part$Year), , drop = FALSE]
    if (nrow(part) < 2L) next
    residual_rows[[region]] <- data.frame(
      RS = as.character(part$RS[-1L]),
      Year = part$Year[-1L],
      residual = diff(part$.yield),
      stringsAsFactors = FALSE
    )
  }
  residuals <- do.call(rbind, residual_rows)
  if (is.null(residuals)) {
    residuals <- data.frame(RS = character(), Year = integer(), residual = numeric())
  }
  structure(list(
    method = "persistence",
    history = data[, c("RS", "Year", ".yield"), drop = FALSE],
    regions = regions,
    rho = 0,
    training_residuals = residuals,
    residual_sigma = if (nrow(residuals)) sqrt(mean(residuals$residual^2)) else NA_real_,
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_persistence <- function(model, new_data, use_ar = TRUE) {
  prediction <- numeric(nrow(new_data))
  for (i in seq_len(nrow(new_data))) {
    history <- model$history[
      as.character(model$history$RS) == as.character(new_data$RS[i]) &
        model$history$Year < new_data$Year[i], , drop = FALSE
    ]
    if (nrow(history)) {
      prediction[i] <- history$.yield[which.max(history$Year)]
    } else {
      region_history <- model$history[
        as.character(model$history$RS) == as.character(new_data$RS[i]), , drop = FALSE
      ]
      prediction[i] <- if (nrow(region_history)) {
        region_history$.yield[which.min(region_history$Year)]
      } else {
        mean(model$history$.yield)
      }
    }
  }
  prediction
}

cy_fit_panel_ridge <- function(
    data, manifest, lambda, smooth_ratio, robust = TRUE,
    robust_iterations = 6L) {
  feature_names <- manifest$Term
  preprocessor <- cy_fit_preprocessor(data, feature_names)
  transformed <- cy_transform(preprocessor, data)
  regions <- as.character(data$RS)
  region_levels <- sort(unique(regions))
  region_design <- cy_region_columns(regions, transformed$year, region_levels)
  design <- cbind(year = transformed$year, transformed$x, region_design)
  penalty <- cy_make_weather_penalty(
    colnames(design), manifest, lambda, smooth_ratio,
    year_factor = 0.05, region_factor = c(0.05, 0.25)
  )
  weights <- rep(1, nrow(data))
  fit <- NULL
  n_iterations <- if (robust) robust_iterations else 1L
  for (iteration in seq_len(n_iterations)) {
    fit <- cy_penalized_intercept(design, data$.yield, penalty, weights)
    fitted <- fit$intercept + as.numeric(design %*% fit$coef)
    if (!robust) break
    new_weights <- cy_robust_weights(data$.yield - fitted)
    if (max(abs(new_weights - weights)) < 1e-4) {
      weights <- new_weights
      break
    }
    weights <- new_weights
  }
  residual <- data$.yield - fitted
  structure(list(
    method = "panel_ridge",
    params = list(lambda = lambda, smooth_ratio = smooth_ratio),
    preprocessor = preprocessor,
    regions = region_levels,
    intercept = fit$intercept,
    coef = setNames(fit$coef, colnames(design)),
    rho = cy_estimate_ar1(regions, data$Year, residual),
    training_residuals = data.frame(RS = regions, Year = data$Year, residual),
    residual_sigma = sqrt(sum(weights * residual^2) / sum(weights)),
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_panel_ridge <- function(model, new_data, use_ar = TRUE) {
  transformed <- cy_transform(model$preprocessor, new_data)
  region_design <- cy_region_columns(
    as.character(new_data$RS), transformed$year, model$regions
  )
  design <- cbind(year = transformed$year, transformed$x, region_design)
  design <- design[, names(model$coef), drop = FALSE]
  prediction <- model$intercept + as.numeric(design %*% model$coef)
  if (use_ar) prediction <- prediction + cy_ar_correction(model, new_data)
  prediction
}

cy_fit_local_ridge <- function(
    data, manifest, lambda, smooth_ratio, robust = TRUE,
    robust_iterations = 6L) {
  feature_names <- manifest$Term
  preprocessor <- cy_fit_preprocessor(data, feature_names)
  transformed <- cy_transform(preprocessor, data)
  regions <- as.character(data$RS)
  region_levels <- sort(unique(regions))
  term_names <- c("year", feature_names)
  penalty <- cy_make_weather_penalty(
    term_names, manifest, lambda, smooth_ratio, year_factor = 0.05
  )
  coefficients <- matrix(0, length(region_levels), length(term_names),
    dimnames = list(region_levels, term_names))
  intercepts <- setNames(numeric(length(region_levels)), region_levels)
  fitted <- numeric(nrow(data))
  weights_all <- rep(1, nrow(data))
  for (region in region_levels) {
    index <- which(regions == region)
    design <- cbind(year = transformed$year[index], transformed$x[index, , drop = FALSE])
    weights <- rep(1, length(index))
    fit <- NULL
    for (iteration in seq_len(if (robust) robust_iterations else 1L)) {
      fit <- cy_penalized_intercept(design, data$.yield[index], penalty, weights)
      regional_fitted <- fit$intercept + as.numeric(design %*% fit$coef)
      if (!robust) break
      new_weights <- cy_robust_weights(data$.yield[index] - regional_fitted)
      if (max(abs(new_weights - weights)) < 1e-4) {
        weights <- new_weights
        break
      }
      weights <- new_weights
    }
    coefficients[region, ] <- fit$coef
    intercepts[region] <- fit$intercept
    fitted[index] <- regional_fitted
    weights_all[index] <- weights
  }
  residual <- data$.yield - fitted
  structure(list(
    method = "local_ridge",
    params = list(lambda = lambda, smooth_ratio = smooth_ratio),
    preprocessor = preprocessor,
    regions = region_levels,
    intercepts = intercepts,
    coefficients = coefficients,
    rho = cy_estimate_ar1(regions, data$Year, residual),
    training_residuals = data.frame(RS = regions, Year = data$Year, residual),
    residual_sigma = sqrt(sum(weights_all * residual^2) / sum(weights_all)),
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_local_ridge <- function(model, new_data, use_ar = TRUE) {
  transformed <- cy_transform(model$preprocessor, new_data)
  design <- cbind(year = transformed$year, transformed$x)
  prediction <- numeric(nrow(new_data))
  for (region in unique(as.character(new_data$RS))) {
    index <- which(as.character(new_data$RS) == region)
    if (!region %in% model$regions) next
    prediction[index] <- model$intercepts[region] +
      as.numeric(design[index, , drop = FALSE] %*% model$coefficients[region, ])
  }
  if (use_ar) prediction <- prediction + cy_ar_correction(model, new_data)
  prediction
}

cy_fit_pcr <- function(data, manifest, components, robust = TRUE, robust_iterations = 6L) {
  feature_names <- manifest$Term
  preprocessor <- cy_fit_preprocessor(data, feature_names)
  transformed <- cy_transform(preprocessor, data)
  decomposition <- svd(transformed$x, nu = 0)
  components <- min(as.integer(components), ncol(decomposition$v), nrow(data) - 2L)
  rotation <- decomposition$v[, seq_len(components), drop = FALSE]
  rownames(rotation) <- feature_names
  colnames(rotation) <- paste0("PC", seq_len(components))
  scores <- transformed$x %*% rotation
  regions <- as.character(data$RS)
  region_levels <- sort(unique(regions))
  region_design <- cy_region_columns(regions, transformed$year, region_levels)
  design <- cbind(year = transformed$year, scores, region_design)
  factors <- rep(1e-4, ncol(design))
  names(factors) <- colnames(design)
  factors[startsWith(names(factors), "region_") &
    !startsWith(names(factors), "region_year_")] <- 0.05
  factors[startsWith(names(factors), "region_year_")] <- 0.25
  penalty <- diag(factors, nrow = length(factors))
  weights <- rep(1, nrow(data))
  fit <- NULL
  for (iteration in seq_len(if (robust) robust_iterations else 1L)) {
    fit <- cy_penalized_intercept(design, data$.yield, penalty, weights)
    fitted <- fit$intercept + as.numeric(design %*% fit$coef)
    if (!robust) break
    new_weights <- cy_robust_weights(data$.yield - fitted)
    if (max(abs(new_weights - weights)) < 1e-4) {
      weights <- new_weights
      break
    }
    weights <- new_weights
  }
  residual <- data$.yield - fitted
  structure(list(
    method = "pcr",
    params = list(components = components),
    preprocessor = preprocessor,
    rotation = rotation,
    regions = region_levels,
    intercept = fit$intercept,
    coef = setNames(fit$coef, colnames(design)),
    rho = cy_estimate_ar1(regions, data$Year, residual),
    training_residuals = data.frame(RS = regions, Year = data$Year, residual),
    residual_sigma = sqrt(sum(weights * residual^2) / sum(weights)),
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_pcr <- function(model, new_data, use_ar = TRUE) {
  transformed <- cy_transform(model$preprocessor, new_data)
  scores <- transformed$x %*% model$rotation
  region_design <- cy_region_columns(
    as.character(new_data$RS), transformed$year, model$regions
  )
  design <- cbind(year = transformed$year, scores, region_design)
  design <- design[, names(model$coef), drop = FALSE]
  prediction <- model$intercept + as.numeric(design %*% model$coef)
  if (use_ar) prediction <- prediction + cy_ar_correction(model, new_data)
  prediction
}

cy_hierarchical_region_prediction <- function(coef, regions, design) {
  prediction <- numeric(length(regions))
  for (region in unique(regions)) {
    index <- which(regions == region)
    if (!region %in% rownames(coef)) next
    prediction[index] <- as.numeric(design[index, , drop = FALSE] %*% coef[region, ])
  }
  prediction
}

cy_fit_hierarchical <- function(
    data, manifest, lambda_global, lambda_region, smooth_ratio,
    robust = TRUE, backfit_iterations = 6L, robust_iterations = 6L) {
  feature_names <- manifest$Term
  preprocessor <- cy_fit_preprocessor(data, feature_names)
  transformed <- cy_transform(preprocessor, data)
  regions <- as.character(data$RS)
  region_levels <- sort(unique(regions))
  global_design <- cbind(year = transformed$year, transformed$x)
  regional_design <- cbind(`(Intercept)` = 1, year = transformed$year, transformed$x)
  global_penalty <- cy_make_weather_penalty(
    colnames(global_design), manifest, lambda_global, smooth_ratio,
    year_factor = 0.05
  )
  regional_penalty <- cy_make_weather_penalty(
    colnames(regional_design), manifest, lambda_region, smooth_ratio,
    year_factor = 0.25
  )
  regional_penalty["(Intercept)", "(Intercept)"] <- lambda_region * 0.05
  regional_coef <- matrix(0, length(region_levels), ncol(regional_design),
    dimnames = list(region_levels, colnames(regional_design)))
  weights <- rep(1, nrow(data))
  total_fitted <- rep(mean(data$.yield), nrow(data))
  global_fit <- NULL
  for (outer in seq_len(if (robust) robust_iterations else 1L)) {
    for (iteration in seq_len(backfit_iterations)) {
      regional_fitted <- cy_hierarchical_region_prediction(
        regional_coef, regions, regional_design
      )
      global_fit <- cy_penalized_intercept(
        global_design, data$.yield - regional_fitted,
        global_penalty, weights
      )
      global_fitted <- global_fit$intercept + as.numeric(global_design %*% global_fit$coef)
      for (region in region_levels) {
        index <- which(regions == region)
        regional_coef[region, ] <- cy_penalized_origin(
          regional_design[index, , drop = FALSE],
          data$.yield[index] - global_fitted[index],
          regional_penalty,
          weights[index]
        )
      }
      updated <- global_fitted + cy_hierarchical_region_prediction(
        regional_coef, regions, regional_design
      )
      if (max(abs(updated - total_fitted)) < 1e-6) {
        total_fitted <- updated
        break
      }
      total_fitted <- updated
    }
    if (!robust) break
    new_weights <- cy_robust_weights(data$.yield - total_fitted)
    if (max(abs(new_weights - weights)) < 1e-4) {
      weights <- new_weights
      break
    }
    weights <- new_weights
  }
  residual <- data$.yield - total_fitted
  structure(list(
    method = "hierarchical",
    params = list(
      lambda_global = lambda_global,
      lambda_region = lambda_region,
      smooth_ratio = smooth_ratio
    ),
    preprocessor = preprocessor,
    regions = region_levels,
    global_intercept = global_fit$intercept,
    global_coef = setNames(global_fit$coef, colnames(global_design)),
    regional_coef = regional_coef,
    rho = cy_estimate_ar1(regions, data$Year, residual),
    training_residuals = data.frame(RS = regions, Year = data$Year, residual),
    residual_sigma = sqrt(sum(weights * residual^2) / sum(weights)),
    training_years = range(data$Year)
  ), class = "cy_model")
}

cy_predict_hierarchical <- function(model, new_data, use_ar = TRUE) {
  transformed <- cy_transform(model$preprocessor, new_data)
  global_design <- cbind(year = transformed$year, transformed$x)
  regional_design <- cbind(`(Intercept)` = 1, year = transformed$year, transformed$x)
  regions <- as.character(new_data$RS)
  prediction <- model$global_intercept +
    as.numeric(global_design %*% model$global_coef) +
    cy_hierarchical_region_prediction(model$regional_coef, regions, regional_design)
  if (use_ar) prediction <- prediction + cy_ar_correction(model, new_data)
  prediction
}

cy_predict_ensemble <- function(model, new_data, use_ar = TRUE) {
  predictions <- vapply(
    model$base_models,
    function(base_model) cy_predict_model(base_model, new_data, use_ar = use_ar),
    numeric(nrow(new_data))
  )
  if (is.null(dim(predictions))) predictions <- matrix(predictions, ncol = 1L)
  model_names <- names(model$base_models)
  if (is.null(model_names)) model_names <- vapply(model$base_models, `[[`, "", "method")
  colnames(predictions) <- model_names
  weights <- model$weights[colnames(predictions)]
  if (anyNA(weights)) stop("Ensemble base models do not match its weights.", call. = FALSE)
  as.numeric(predictions %*% weights)
}

cy_fit_model <- function(method, data, manifest, params = list(), robust = TRUE) {
  model <- switch(method,
    trend = cy_fit_trend(data),
    persistence = cy_fit_persistence(data),
    panel_ridge = cy_fit_panel_ridge(
      data, manifest, params$lambda, params$smooth_ratio, robust
    ),
    local_ridge = cy_fit_local_ridge(
      data, manifest, params$lambda, params$smooth_ratio, robust
    ),
    pcr = cy_fit_pcr(data, manifest, params$components, robust),
    hierarchical = cy_fit_hierarchical(
      data, manifest, params$lambda_global, params$lambda_region,
      params$smooth_ratio, robust
    ),
    stress_lag = cy_fit_stress_lag(
      data, manifest, params$lambda, params$smooth_ratio, params$threshold,
      params$temperature_variable, params$precipitation_variable, robust
    ),
    stop("Unknown method: ", method, call. = FALSE)
  )
  x <- as.matrix(data[, manifest$Term, drop = FALSE])
  scale <- apply(x, 2L, sd)
  scale[!is.finite(scale) | scale < 1e-10] <- 1
  model$weather_support <- list(
    terms = manifest$Term, minimum = apply(x, 2L, min),
    maximum = apply(x, 2L, max), center = colMeans(x), scale = scale,
    regions = sort(unique(as.character(data$RS)))
  )
  model
}

cy_predict_model <- function(model, new_data, use_ar = TRUE) {
  switch(model$method,
    trend = cy_predict_trend(model, new_data, use_ar),
    persistence = cy_predict_persistence(model, new_data, use_ar),
    panel_ridge = cy_predict_panel_ridge(model, new_data, use_ar),
    local_ridge = cy_predict_local_ridge(model, new_data, use_ar),
    pcr = cy_predict_pcr(model, new_data, use_ar),
    hierarchical = cy_predict_hierarchical(model, new_data, use_ar),
    stress_lag = cy_predict_stress_lag(model, new_data, use_ar),
    ensemble = cy_predict_ensemble(model, new_data, use_ar),
    stop("Unknown fitted method: ", model$method, call. = FALSE)
  )
}

cy_parameter_sets <- function(method, config) {
  if (method %in% c("trend", "persistence")) return(list(list()))
  grid <- switch(method,
    panel_ridge = expand.grid(
      lambda = config$grids$panel_ridge$lambda,
      smooth_ratio = config$grids$panel_ridge$smooth_ratio,
      KEEP.OUT.ATTRS = FALSE
    ),
    local_ridge = expand.grid(
      lambda = config$grids$local_ridge$lambda,
      smooth_ratio = config$grids$local_ridge$smooth_ratio,
      KEEP.OUT.ATTRS = FALSE
    ),
    pcr = expand.grid(
      components = config$grids$pcr$components,
      KEEP.OUT.ATTRS = FALSE
    ),
    hierarchical = expand.grid(
      lambda_global = config$grids$hierarchical$lambda_global,
      lambda_region = config$grids$hierarchical$lambda_region,
      smooth_ratio = config$grids$hierarchical$smooth_ratio,
      KEEP.OUT.ATTRS = FALSE
    ),
    stress_lag = expand.grid(
      lambda = config$grids$stress_lag$lambda,
      smooth_ratio = config$grids$stress_lag$smooth_ratio,
      threshold = config$grids$stress_lag$threshold,
      KEEP.OUT.ATTRS = FALSE
    )
  )
  lapply(seq_len(nrow(grid)), function(i) {
    parameters <- as.list(grid[i, , drop = FALSE])
    if (method == "stress_lag") {
      parameters$temperature_variable <- config$stress_temperature
      parameters$precipitation_variable <- config$stress_precipitation
    }
    parameters
  })
}
