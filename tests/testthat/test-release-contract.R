test_that("later responses and weather cannot change tuning decisions", {
  data <- synthetic_crop_data()
  config <- small_comparison_config()
  reference <- compare_crop_models(data, config, 2015, 2016, verbose = FALSE)
  changed <- data
  changed$panel$.yield[changed$panel$Year >= 2010 & changed$panel$Year <= 2015] <-
    changed$panel$.yield[changed$panel$Year >= 2010 & changed$panel$Year <= 2015] + 100
  for (term in changed$manifest$Term) {
    changed$panel[[term]][changed$panel$Year == 2016] <- 1000
  }
  refitted <- compare_crop_models(changed, config, 2015, 2016, verbose = FALSE)
  expect_identical(refitted$selected_method, reference$selected_method)
  expect_equal(refitted$tuning_method_metrics, reference$tuning_method_metrics)
  for (method in names(reference$results)) {
    expect_equal(refitted$results[[method]]$selected_params,
      reference$results[[method]]$selected_params)
    expect_equal(refitted$results[[method]]$tuning_predictions,
      reference$results[[method]]$tuning_predictions)
    first_year <- reference$year_split$evaluation[1]
    before <- subset(reference$results[[method]]$evaluation_predictions, Year == first_year)
    after <- subset(refitted$results[[method]]$evaluation_predictions, Year == first_year)
    expect_equal(after$Predicted, before$Predicted)
  }
})

test_that("an impossible temporal split fails before fitting", {
  expect_error(compare_crop_models(
    synthetic_crop_data(),
    crop_model_config(methods = "trend", initial_fraction = 0.85,
      tuning_fraction = 0.01),
    2015, 2016, verbose = FALSE
  ), "four tuning years")
})

test_that("metrics and national data reject ambiguous row alignment", {
  expect_error(yield_metrics(1:3, 1:2), "same length")
  data <- synthetic_crop_data()
  national <- rbind(data$national_yields, data$national_yields[1, ])
  expect_error(prepare_crop_data(data$panel, data$manifest,
    national_yields = national), "unique year")
})

test_that("public synthetic example predicts without modifying the random state", {
  set.seed(421)
  before <- .Random.seed
  data <- synthetic_crop_example()
  expect_identical(.Random.seed, before)
  expect_true(all(is.na(data$panel$.yield[data$panel$Year == 2016])))
  fitted <- fit_crop_model(data, "trend")
  expect_true(all(is.finite(predict(fitted,
    data$panel[data$panel$Year == 2016, ]))))
})

test_that("bundled national observations are not unweighted provincial means", {
  data <- read_crop_data(poland_example_path(), "wheat", 7)
  expect_equal(nrow(data$national_yields), 0)
  comparison <- compare_crop_models(data,
    crop_model_config(methods = "trend"), 2018, 2019, verbose = FALSE)
  expect_true(all(is.finite(comparison$metrics$RMSE)))
  national <- comparison$national_cv_predictions
  expect_true(all(is.na(national$OfficialNationalYield)))
  expect_true(all(is.finite(national$ObservedWeighted)))
})
