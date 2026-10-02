test_that("held calibration and evaluation responses cannot enter model selection", {
  data <- synthetic_crop_data()
  config <- small_comparison_config()
  config$calibration_years <- 2L
  original <- compare_crop_models(data, config, 2015, 2016, verbose = FALSE)
  expect_equal(original$year_split$calibration, 2010:2011)
  expect_equal(original$year_split$evaluation, 2012:2015)
  changed <- data
  later <- changed$panel$Year >= 2010
  changed$panel$.yield[later] <- changed$panel$.yield[later] + 80
  refitted <- compare_crop_models(changed, config, 2015, 2016, verbose = FALSE)
  expect_identical(refitted$selected_method, original$selected_method)
  expect_equal(refitted$tuning_method_metrics, original$tuning_method_metrics)
  for (method in names(original$results)) {
    expect_equal(refitted$results[[method]]$selected_params, original$results[[method]]$selected_params)
    expect_equal(subset(refitted$results[[method]]$calibration_predictions, Year == 2010)$Predicted,
      subset(original$results[[method]]$calibration_predictions, Year == 2010)$Predicted)
    cal <- original$results[[method]]$calibration_predictions
    expect_equal(original$results[[method]]$interval_half_width_80,
      yieldlag:::cy_empirical_half_width(cal$Observed, cal$Predicted))
  }
  evaluation_changed <- data
  evaluation_changed$panel$.yield[evaluation_changed$panel$Year >= 2012] <- 900
  evaluated <- compare_crop_models(evaluation_changed, config, 2015, 2016, verbose = FALSE)
  expect_equal(vapply(evaluated$results, `[[`, numeric(1), "interval_half_width_80"),
    vapply(original$results, `[[`, numeric(1), "interval_half_width_80"))
  expect_error(crop_model_config(calibration_years = 1.5), "non-negative integer")
  for (method in names(original$results)) {
    national <- subset(original$national_cv_predictions,
      Method == method & Phase == "calibration")
    expect_equal(unique(national$NationalHalfWidth80),
      yieldlag:::cy_empirical_half_width(yieldlag:::cy_national_observed(national),
        national$PredictedWeighted))
  }
})

test_that("stress ablations remove terms and preserve exact decomposition", {
  data <- synthetic_stress_example()
  model <- fit_crop_model(data, "stress_lag", parameters = list(lambda = 10,
    smooth_ratio = 0, components = "linear", regional_effects = FALSE), robust = FALSE)
  expect_equal(unique(model$engine$stress_feature_manifest$Component), "linear")
  expect_false(any(startsWith(names(model$engine$coef), "region_")))
  part <- subset(data$panel, Year == 2031)
  explanation <- explain_crop_prediction(model, part)
  expect_equal(explanation$Prediction, as.numeric(predict(model, part)), tolerance = 1e-9)
  expect_equal(explanation$Regional, rep(0, nrow(part)))
  expect_equal(explanation$UpperTail, rep(0, nrow(part)))
  expect_error(fit_crop_model(data, "stress_lag", list(components = "upper_tail")), "include linear")
})

test_that("paired bootstrap retains year clusters and random state", {
  p <- expand.grid(RS = c("A", "B"), Year = 2001:2008,
    Method = c("reference", "alternative"), stringsAsFactors = FALSE)
  p$Observed <- 10 + p$Year - 2000
  p$Predicted <- p$Observed + ifelse(p$Method == "reference", 2, 1)
  set.seed(123)
  previous <- .Random.seed
  result <- compare_crop_errors(p, "reference", repetitions = 100)
  expect_identical(.Random.seed, previous)
  expect_equal(result$RMSEDifference, -1)
  expect_equal(c(result$Lower, result$Upper), c(-1, -1))
  expect_equal(result$Years, 8)
  expect_error(compare_crop_errors(p[-1, ], "reference", repetitions = 100), "identical paired")
})
