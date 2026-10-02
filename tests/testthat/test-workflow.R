test_that("comparison preserves chronological phases and tuning-only selection", {
  data <- synthetic_crop_data()
  comparison <- compare_crop_models(
    data, small_comparison_config(),
    last_yield_year = 2015, predict_through = 2016, verbose = FALSE
  )
  expect_s3_class(comparison, "crop_model_comparison")
  expect_identical(comparison$year_split$tuning, 2006:2009)
  expect_identical(comparison$year_split$evaluation, 2010:2015)
  expect_equal(
    comparison$selected_method,
    comparison$tuning_method_metrics$Method[which.min(comparison$tuning_method_metrics$RMSE)]
  )
  expect_true(all(
    comparison$province_cv_predictions$Year[
      comparison$province_cv_predictions$Phase == "evaluation"
    ] %in% 2010:2015
  ))
  expect_equal(sum(comparison$metrics$SelectedByTuning), 2)
})

test_that("final base and ensemble models predict through the public interface", {
  data <- synthetic_crop_data()
  comparison <- compare_crop_models(
    data, small_comparison_config(), 2015, 2016, verbose = FALSE
  )
  future <- data$panel[data$panel$Year == 2016, ]
  for (method in names(comparison$results)) {
    model <- get_crop_model(comparison, method)
    prediction <- predict(model, future, interval = "prediction")
    expect_equal(nrow(prediction), 4)
    expect_true(all(is.finite(as.matrix(prediction))))
    expect_true(all(prediction$lower < prediction$upper))
  }
})

test_that("artifact writer produces an auditable and protected bundle", {
  data <- synthetic_crop_data()
  comparison <- compare_crop_models(
    data,
    crop_model_config(methods = "trend", weather_variables = "TMP"),
    2015, 2016, verbose = FALSE
  )
  destination <- file.path(tempdir(), paste0("crop-results-", Sys.getpid()))
  dir.create(destination, recursive = TRUE, showWarnings = FALSE)
  write_crop_results(comparison, destination, overwrite = TRUE)
  required <- c(
    "analysis_config.dput", "artifact_checksums.csv", "all_tuning_results.csv",
    "method_selection_tuning.csv", "model_comparison.rds", "model_metrics.csv",
    "province_cv_predictions.csv", "report.md", "run_manifest.txt",
    "session_info.txt"
  )
  expect_true(all(file.exists(file.path(destination, required))))
  checksums <- read.csv(file.path(destination, "artifact_checksums.csv"))
  expect_true(all(checksums$MD5 == unname(tools::md5sum(
    file.path(destination, checksums$File)
  ))))
  expect_error(write_crop_results(comparison, destination), "Existing result")
})
