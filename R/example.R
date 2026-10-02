#' Deterministic synthetic crop-yield example
#'
#' Four fictional regions with annual yields from 2000 through 2015 and
#' weather through 2016. Values are generated from a known trend and monthly
#' weather response, without random numbers or real agricultural observations.
#' This example demonstrates the API; its scores are not scientific evidence.
#'
#' @return A [prepare_crop_data()] result with twelve monthly temperature terms.
#' @export
#' @examples
#' data <- synthetic_crop_example()
#' model <- fit_crop_model(data, "trend")
#' predict(model, data$panel[data$panel$Year == 2016, ])
synthetic_crop_example <- function() {
  regions <- LETTERS[1:4]
  manifest <- data.frame(
    Term = paste0("TMP_m", sprintf("%02d", 1:12)),
    Variable = "TMP", CalendarMonth = 1:12, AgriculturalPosition = 1:12
  )
  panel <- expand.grid(RS = regions, Year = 2000:2016, stringsAsFactors = FALSE)
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
    data.frame(Year = year,
      OfficialNationalYield = weighted.mean(part$.yield, areas$Area))
  }))
  prepare_crop_data(
    panel, manifest, areas, national,
    crop = "synthetic", harvest_month = 12, weather_variables = "TMP",
    provenance = list(type = "deterministic_synthetic_example")
  )
}
