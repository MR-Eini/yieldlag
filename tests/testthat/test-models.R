test_that("every base method fits and predicts finite yields", {
  data <- synthetic_crop_data()
  parameters <- list(
    trend = list(),
    persistence = list(),
    panel_ridge = list(lambda = 100, smooth_ratio = 10),
    local_ridge = list(lambda = 100, smooth_ratio = 10),
    pcr = list(components = 3L),
    hierarchical = list(lambda_global = 100, lambda_region = 300, smooth_ratio = 10)
  )
  future <- data$panel[data$panel$Year == 2016, ]
  for (method in names(parameters)) {
    model <- fit_crop_model(data, method, parameters[[method]])
    expect_s3_class(model, "crop_yield_model")
    expect_true(all(is.finite(predict(model, future))))
  }
})

test_that("direct fits cannot imply an uncalibrated interval", {
  data <- synthetic_crop_data()
  model <- fit_crop_model(data, "trend")
  expect_error(
    predict(model, data$panel[1:2, ], interval = "prediction"),
    "no calibrated interval"
  )
})

test_that("metrics distinguish predictive R-squared and correlation", {
  metrics <- yield_metrics(c(1, 2, 3), c(2, 3, 4))
  expect_equal(metrics$Bias, 1)
  expect_equal(metrics$Cor_R2, 1)
  expect_lt(metrics$R2, 1)
})
