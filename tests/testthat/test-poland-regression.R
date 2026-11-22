test_that("the Poland trend baseline reproduces the website RMSE", {
  reference <- data.frame(
    crop = c("barley", "wheat"),
    harvest_month = c(6L, 7L),
    national_rmse = c(3.57692835251392, 3.77878322026459),
    provincial_rmse = c(4.63012724138850, 5.27240273391920)
  )
  config <- crop_model_config(methods = "trend", robust = TRUE)
  for (i in seq_len(nrow(reference))) {
    data <- read_crop_data(poland_example_path(), reference$crop[i],
                           reference$harvest_month[i])
    result <- compare_crop_models(data, config, 2018, 2019, verbose = FALSE)
    expect_identical(result$year_split$evaluation, 2012:2018)
    metrics <- result$metrics
    actual <- metrics$RMSE[match(c("National", "Province-year"), metrics$Level)]
    expect_equal(actual, c(reference$national_rmse[i], reference$provincial_rmse[i]),
                 tolerance = 1e-8)
  }
})
