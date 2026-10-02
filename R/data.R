# Raw-data ingestion and deterministic agricultural-year construction.

cy_build_manifest <- function(variables, harvest_month) {
  calendar_months <- c(
    if (harvest_month < 12) (harvest_month + 1L):12L else integer(),
    1L:harvest_month
  )
  result <- do.call(rbind, lapply(variables, function(variable) {
    data.frame(
      Term = paste0(variable, "_m", sprintf("%02d", calendar_months)),
      Variable = variable,
      CalendarMonth = calendar_months,
      AgriculturalPosition = seq_along(calendar_months),
      stringsAsFactors = FALSE
    )
  }))
  rownames(result) <- NULL
  result
}

cy_weather_to_years <- function(weather, region, variables, harvest_month, manifest) {
  rows <- list()
  expected_months <- manifest$CalendarMonth[manifest$Variable == variables[1]]
  for (year in (min(weather$yyyy) + 1L):max(weather$yyyy)) {
    selected <- weather[
      (weather$yyyy == year - 1L & weather$mm > harvest_month) |
        (weather$yyyy == year & weather$mm <= harvest_month),
      , drop = FALSE
    ]
    selected_order <- match(expected_months, selected$mm)
    if (nrow(selected) != 12L || anyNA(selected_order)) next
    selected <- selected[selected_order, , drop = FALSE]
    values <- unlist(lapply(variables, function(variable) selected[[variable]]), use.names = FALSE)
    row <- data.frame(RS = as.character(region), Year = year, stringsAsFactors = FALSE)
    for (j in seq_along(manifest$Term)) row[[manifest$Term[j]]] <- values[j]
    rows[[as.character(year)]] <- row
  }
  do.call(rbind, rows)
}

cy_load_raw_data <- function(data_dir, crop, variables, harvest_month) {
  weather_dir <- file.path(data_dir, "weather")
  yield_path <- file.path(data_dir, "yield.csv")
  area_path <- file.path(data_dir, "crop_areas.csv")
  weather_files <- sort(list.files(weather_dir, pattern = "[.]dat$", full.names = TRUE))
  if (!length(weather_files)) stop("No weather files found in ", weather_dir, call. = FALSE)
  manifest <- cy_build_manifest(variables, harvest_month)

  weather_tables <- lapply(weather_files, function(path) {
    weather <- read.table(path, header = TRUE, check.names = FALSE)
    required <- c("yyyy", "mm", variables)
    missing <- setdiff(required, names(weather))
    if (length(missing)) {
      stop(basename(path), " is missing ", paste(missing, collapse = ", "), call. = FALSE)
    }
    if (any(!is.finite(as.matrix(weather[, variables, drop = FALSE])))) {
      stop(basename(path), " contains missing or non-finite weather values.", call. = FALSE)
    }
    region <- sub("^pl_([0-9]+)[.]dat$", "\\1", basename(path))
    cy_weather_to_years(weather[, required], region, variables, harvest_month, manifest)
  })
  weather_panel <- do.call(rbind, weather_tables)
  rownames(weather_panel) <- NULL

  yields <- read.csv(yield_path, check.names = FALSE, stringsAsFactors = FALSE)
  names(yields)[1] <- "Year"
  if (!crop %in% names(yields)) stop("Crop not found in yield file: ", crop, call. = FALSE)
  province_yields <- yields[
    !is.na(yields$RS) & yields$RS > 999,
    c("RS", "Year", crop),
    drop = FALSE
  ]
  province_yields$RS <- as.character(province_yields$RS)
  names(province_yields)[3] <- ".yield"
  panel <- merge(weather_panel, province_yields, by = c("RS", "Year"), all.x = TRUE)
  panel <- panel[order(panel$Year, panel$RS), c("RS", "Year", ".yield", manifest$Term)]

  areas <- read.csv(area_path, check.names = FALSE, stringsAsFactors = FALSE)
  names(areas)[1] <- "RS"
  if (!crop %in% names(areas)) stop("Crop not found in area file: ", crop, call. = FALSE)
  province_areas <- areas[
    !is.na(areas$RS) & areas$RS > 999,
    c("RS", crop),
    drop = FALSE
  ]
  province_areas$RS <- as.character(province_areas$RS)
  names(province_areas)[2] <- "Area"

  aggregate_yields <- yields[is.na(yields$RS) | yields$RS < 999, , drop = FALSE]
  if ("Region" %in% names(aggregate_yields)) {
    poland <- toupper(trimws(aggregate_yields$Region)) == "POLAND"
    if (any(poland)) aggregate_yields <- aggregate_yields[poland, , drop = FALSE]
  }
  national_yields <- aggregate_yields[, c("Year", crop), drop = FALSE]
  names(national_yields)[2] <- "OfficialNationalYield"

  list(
    panel = panel,
    manifest = manifest,
    areas = province_areas,
    national_yields = national_yields,
    provenance = list(
      weather_files = normalizePath(weather_files, winslash = "/"),
      yield_file = normalizePath(yield_path, winslash = "/"),
      area_file = normalizePath(area_path, winslash = "/")
    )
  )
}
