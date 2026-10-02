#' Synthetic seasonal weather and compound-stress example
#'
#' Six fictional regions with monthly temperature and precipitation for April
#' through July, 1990--2031. Yield follows a declared trend plus asymmetric
#' temperature/precipitation terms and a June hot-dry interaction. Observations
#' through 2030 are supplied; 2031 is a forecast year. The deterministic formula
#' illustrates nonlinear estimation and does not represent measured crop response.
#'
#' @return A `crop_yield_data` object. The full data-generating equation is in
#'   the function source; no random-number state is read or changed.
#' @export
#' @examples
#' data <- synthetic_stress_example()
#' model <- fit_crop_model(data, "stress_lag", parameters = list(
#'   lambda = 1, smooth_ratio = 0, threshold = 0.75,
#'   temperature_variable = "TMP", precipitation_variable = "PCP"),
#'   robust = FALSE)
#' explain_crop_prediction(model, subset(data$panel, Year == 2031))
synthetic_stress_example <- function() {
  months <- 4:7
  manifest <- do.call(rbind, lapply(c("TMP", "PCP"), function(variable) {
    data.frame(Term = paste0(variable, "_m", sprintf("%02d", months)),
      Variable = variable, CalendarMonth = months, AgriculturalPosition = 1:4)
  }))
  panel <- expand.grid(RS = LETTERS[1:6], Year = 1990:2031, stringsAsFactors = FALSE)
  region <- match(panel$RS, LETTERS[1:6])
  time <- panel$Year - 1990
  latent <- list()
  for (month in months) {
    temperature <- sin(1.73 * time + 0.71 * region + 1.1 * month) +
      0.55 * cos(2.31 * time + 0.43 * region - month)
    precipitation <- sin(2.17 * time + 1.31 * region + 0.4 * month) +
      0.55 * cos(1.11 * time - 0.93 * region + month)
    panel[[paste0("TMP_m", sprintf("%02d", month))]] <-
      14 + month + 0.8 * region + 5 * temperature
    panel[[paste0("PCP_m", sprintf("%02d", month))]] <-
      70 + 2 * region + 25 * precipitation
    if (month == 6) latent <- list(temperature = temperature, precipitation = precipitation)
  }
  heat <- pmax(latent$temperature - 0.6, 0)
  dry <- pmax(-latent$precipitation - 0.6, 0)
  panel$.yield <- 45 + 1.5 * region + 0.18 * time -
    7 * heat - 5 * dry - 9 * heat * dry + 0.15 * sin(time + region)
  panel$.yield[panel$Year == 2031] <- NA_real_
  prepare_crop_data(panel, manifest,
    areas = data.frame(RS = LETTERS[1:6], Area = 1:6), crop = "synthetic_stress",
    harvest_month = 7, weather_variables = c("TMP", "PCP"),
    provenance = list(type = "deterministic_compound_stress_example"))
}
