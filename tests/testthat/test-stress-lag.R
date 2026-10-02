stress_test_config <- function() {
  crop_model_config(methods = c("panel_ridge", "stress_lag", "ensemble"),
    weather_variables = c("TMP", "PCP"), robust = FALSE,
    stress_temperature = "TMP", stress_precipitation = "PCP",
    grids = list(panel_ridge = list(lambda = c(0.1, 1, 10), smooth_ratio = 0),
      stress_lag = list(lambda = c(0.1, 1, 10), smooth_ratio = 0, threshold = c(0.5, 0.75, 1)),
      ensemble = list(shrinkage = c(0, 10))))
}

test_that("stress features implement the declared asymmetric and compound basis", {
  data <- synthetic_stress_example()
  model <- fit_crop_model(data, "stress_lag", list(lambda = 1, smooth_ratio = 0,
    threshold = 0.75, temperature_variable = "TMP", precipitation_variable = "PCP"),
    robust = FALSE)
  engine <- model$engine
  row <- data$panel[1, ]
  region <- row$RS
  row$TMP_m06 <- engine$climatology$centers[region, "TMP_m06"] +
    2 * engine$climatology$scale["TMP_m06"]
  row$PCP_m06 <- engine$climatology$centers[region, "PCP_m06"] -
    1.5 * engine$climatology$scale["PCP_m06"]
  basis <- yieldlag:::cy_stress_prediction_basis(engine, row)
  expect_equal(basis$panel$upper_tail__TMP_m06, 1.25)
  expect_equal(basis$panel$lower_tail__PCP_m06, 0.75)
  expect_equal(basis$panel$compound_hot_dry__m06, 1.25 * 0.75)
  expect_equal(nrow(engine$stress_feature_manifest), 28)
  expect_true(all(is.finite(coef(model))))
})

test_that("decompositions exactly reconstruct predictions including residual correction", {
  data <- synthetic_stress_example()
  model <- fit_crop_model(data, "stress_lag", robust = FALSE)
  for (ar in c(TRUE, FALSE)) {
    future <- subset(data$panel, Year == 2031)
    components <- explain_crop_prediction(model, future, use_ar = ar)
    expect_equal(components$Prediction, as.numeric(predict(model, future, use_ar = ar)),
      tolerance = 1e-10)
    expect_equal(components$HotDry, rep(0, nrow(future)))
  }
  expect_error(explain_crop_prediction(fit_crop_model(data, "trend"), data$panel),
    "supports stress_lag")
})

test_that("future weather does not enter stress climatology or tuning", {
  data <- synthetic_stress_example()
  reference <- compare_crop_models(data, stress_test_config(), 2030, 2031, verbose = FALSE)
  changed <- data
  evaluation <- reference$year_split$evaluation
  changed$panel$.yield[changed$panel$Year %in% evaluation] <-
    changed$panel$.yield[changed$panel$Year %in% evaluation] + 100
  for (term in changed$manifest$Term) changed$panel[[term]][changed$panel$Year == 2031] <- 10000
  refitted <- compare_crop_models(changed, stress_test_config(), 2030, 2031, verbose = FALSE)
  expect_identical(refitted$selected_method, reference$selected_method)
  expect_equal(refitted$results$stress_lag$selected_params, reference$results$stress_lag$selected_params)
  expect_equal(refitted$results$stress_lag$tuning_predictions,
    reference$results$stress_lag$tuning_predictions)
  first <- evaluation[1]
  expect_equal(subset(refitted$results$stress_lag$evaluation_predictions, Year == first)$Predicted,
    subset(reference$results$stress_lag$evaluation_predictions, Year == first)$Predicted)
  expect_equal(refitted$results$stress_lag$final_model$climatology,
    reference$results$stress_lag$final_model$climatology)
})

test_that("the nonlinear estimator recovers an independent compound-stress fixture", {
  comparison <- compare_crop_models(synthetic_stress_example(), stress_test_config(),
    2030, 2031, verbose = FALSE)
  metrics <- subset(comparison$metrics, Level == "Province-year")
  nonlinear <- metrics$RMSE[metrics$Method == "stress_lag"]
  linear <- metrics$RMSE[metrics$Method == "panel_ridge"]
  expect_lt(nonlinear, 0.75 * linear)
  model <- get_crop_model(comparison, "stress_lag")
  future <- subset(comparison$prediction_panel, Year == 2031)
  expect_true(all(is.finite(as.matrix(predict(model, future, interval = "prediction")))))
  expect_equal(explain_crop_prediction(model, future)$Prediction,
    as.numeric(predict(model, future)), tolerance = 1e-10)
  folder <- tempfile("stress-results-")
  write_crop_results(comparison, folder)
  expect_true(all(file.exists(file.path(folder, c("stress_basis_coefficients.csv",
    "stress_prediction_components.csv", "prediction_support.csv")))))
})

test_that("support diagnostics use training data without changing predictions", {
  data <- synthetic_stress_example()
  model <- fit_crop_model(data, "panel_ridge", robust = FALSE)
  row <- data$panel[1, ]
  support <- prediction_support(model, row)
  expect_equal(support$OutsideTerms, 0)
  row$TMP_m06 <- max(data$panel$TMP_m06) + 100
  expect_equal(prediction_support(model, row)$OutsideTerms, 1)
  row$RS <- "unseen"
  expect_true(prediction_support(model, row)$UnseenRegion)
  training <- subset(data$panel, is.finite(.yield))
  expect_equal(model$engine$weather_support$maximum,
    apply(as.matrix(training[, data$manifest$Term]), 2, max))
})

test_that("stress configuration rejects missing pairs and invalid thresholds", {
  data <- synthetic_stress_example()
  expect_error(crop_model_config(stress_temperature = "TMP"), "both")
  expect_error(fit_crop_model(data, "stress_lag", list(threshold = 0)), "positive")
  expect_error(fit_crop_model(data, "stress_lag", list(temperature_variable = "TMP",
    precipitation_variable = "absent")), "absent")
  altered <- data
  altered$manifest$AgriculturalPosition[altered$manifest$Variable == "PCP"] <- 4:1
  expect_error(fit_crop_model(altered, "stress_lag", list(temperature_variable = "TMP",
    precipitation_variable = "PCP")), "matching seasonal")
  set.seed(67)
  before <- .Random.seed
  synthetic_stress_example()
  expect_identical(.Random.seed, before)
})
