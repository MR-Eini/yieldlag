synthetic_crop_data <- function() {
  years <- 2000:2016
  regions <- LETTERS[1:4]
  manifest <- data.frame(
    Term = paste0("TMP_m", sprintf("%02d", 1:12)),
    Variable = "TMP",
    CalendarMonth = 1:12,
    AgriculturalPosition = 1:12,
    stringsAsFactors = FALSE
  )
  panel <- expand.grid(RS = regions, Year = years, stringsAsFactors = FALSE)
  region_index <- match(panel$RS, regions)
  for (month in 1:12) {
    panel[[manifest$Term[month]]] <-
      sin((panel$Year - 1997 + month) / 3) + 0.15 * region_index + month / 30
  }
  panel$.yield <- 25 + 1.8 * region_index + 0.45 * (panel$Year - 2000) +
    1.4 * panel$TMP_m03 - 0.7 * panel$TMP_m08 +
    0.25 * cos(panel$Year + region_index)
  panel$.yield[panel$Year == 2016] <- NA_real_
  areas <- data.frame(RS = regions, Area = c(2, 3, 4, 5))
  national <- do.call(rbind, lapply(2000:2015, function(year) {
    part <- panel[panel$Year == year, ]
    data.frame(
      Year = year,
      OfficialNationalYield = weighted.mean(part$.yield, areas$Area)
    )
  }))
  prepare_crop_data(
    panel, manifest, areas, national,
    crop = "synthetic", harvest_month = 12,
    weather_variables = "TMP",
    provenance = list(type = "deterministic_test_fixture")
  )
}

small_comparison_config <- function() {
  crop_model_config(
    methods = c("trend", "panel_ridge", "ensemble"),
    weather_variables = "TMP",
    grids = list(
      panel_ridge = list(lambda = c(10, 100), smooth_ratio = 0),
      ensemble = list(shrinkage = c(0, 10))
    )
  )
}
