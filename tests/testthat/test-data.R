test_that("in-memory constructor normalizes and validates the data contract", {
  data <- synthetic_crop_data()
  expect_s3_class(data, "crop_yield_data")
  expect_equal(length(unique(data$panel$RS)), 4)
  expect_equal(nrow(data$manifest), 12)
  expect_equal(data$aggregation, "supplied_area")
  expect_equal(range(data$panel$Year), c(2000L, 2016L))
})

test_that("constructor rejects duplicate keys and non-finite weather", {
  data <- synthetic_crop_data()
  duplicate <- rbind(data$panel, data$panel[1, ])
  expect_error(
    prepare_crop_data(duplicate, data$manifest),
    "at most one row"
  )
  broken <- data$panel
  broken[[data$manifest$Term[1]]][1] <- NA_real_
  expect_error(prepare_crop_data(broken, data$manifest), "must be finite")
})

test_that("bundled case-study data rebuild the declared monthly matrix", {
  path <- poland_example_path()
  expect_true(file.exists(file.path(path, "yield.csv")))
  wheat <- read_crop_data(path, "wheat", 7)
  expect_equal(nrow(wheat$manifest), 84)
  expect_identical(
    wheat$manifest$Term[1:12],
    paste0("SLR_m", sprintf("%02d", c(8:12, 1:7)))
  )
  expect_false(any(grepl("^(SPI|SPEI|SMI)", wheat$manifest$Variable)))
})

test_that("configuration rejects ambiguous settings", {
  expect_error(crop_model_config(methods = "unknown"), "Unknown methods")
  expect_error(crop_model_config(interval_level = 0.9), "supports interval_level")
  expect_error(
    crop_model_config(initial_fraction = 0.7, tuning_fraction = 0.25),
    "leave at least"
  )
})
