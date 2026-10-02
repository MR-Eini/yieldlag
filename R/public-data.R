cy_validate_manifest <- function(manifest) {
  manifest <- as.data.frame(manifest, stringsAsFactors = FALSE)
  canonical <- c("Term", "Variable", "CalendarMonth", "AgriculturalPosition")
  aliases <- c(
    term = "Term", variable = "Variable", calendar_month = "CalendarMonth",
    agricultural_position = "AgriculturalPosition"
  )
  for (alias in names(aliases)) {
    if (alias %in% names(manifest) && !aliases[[alias]] %in% names(manifest)) {
      names(manifest)[names(manifest) == alias] <- aliases[[alias]]
    }
  }
  missing <- setdiff(canonical, names(manifest))
  if (length(missing)) {
    stop("manifest is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  manifest <- manifest[, canonical, drop = FALSE]
  manifest$Term <- as.character(manifest$Term)
  manifest$Variable <- as.character(manifest$Variable)
  manifest$CalendarMonth <- as.integer(manifest$CalendarMonth)
  manifest$AgriculturalPosition <- as.integer(manifest$AgriculturalPosition)
  if (anyNA(manifest) || anyDuplicated(manifest$Term) ||
      any(!manifest$CalendarMonth %in% 1:12) ||
      any(manifest$AgriculturalPosition < 1L)) {
    stop("manifest contains invalid or duplicated term definitions.", call. = FALSE)
  }
  manifest
}

#' Construct crop-yield data from an in-memory panel
#'
#' This constructor makes the package independent of the Poland file layout.
#' Column mappings are explicit; internally they are normalized to `RS`,
#' `Year`, `.yield`, and `Area`.
#'
#' @param panel Data frame with one row per region and year plus all terms in
#'   `manifest`.
#' @param manifest Data frame describing weather terms. It must contain either
#'   `Term`, `Variable`, `CalendarMonth`, `AgriculturalPosition`, or their
#'   snake-case equivalents.
#' @param areas Optional data frame containing one aggregation weight per
#'   region. If omitted, equal weights are used and this is recorded.
#' @param national_yields Optional data frame with independently observed
#'   national yields.
#' @param region,year,yield Names of columns in `panel`.
#' @param area_region,area Names of region and weight columns in `areas`.
#' @param national_year,national_yield Names of columns in `national_yields`.
#' @param crop Optional crop label.
#' @param harvest_month Optional integer from 1 through 12.
#' @param weather_variables Optional vector of weather-variable labels.
#' @param provenance Optional named list describing data sources.
#'
#' @return An object of class `crop_yield_data`.
#' @export
prepare_crop_data <- function(
    panel, manifest, areas = NULL, national_yields = NULL,
    region = "RS", year = "Year", yield = ".yield",
    area_region = region, area = "Area",
    national_year = "Year", national_yield = "OfficialNationalYield",
    crop = NA_character_, harvest_month = NA_integer_,
    weather_variables = NULL, provenance = list(type = "in_memory")) {
  panel <- as.data.frame(panel, stringsAsFactors = FALSE)
  manifest <- cy_validate_manifest(manifest)
  required <- c(region, year, yield, manifest$Term)
  missing <- setdiff(required, names(panel))
  if (length(missing)) {
    stop("panel is missing: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  normalized <- data.frame(
    RS = as.character(panel[[region]]),
    Year = as.integer(panel[[year]]),
    .yield = as.numeric(panel[[yield]]),
    stringsAsFactors = FALSE
  )
  for (term in manifest$Term) normalized[[term]] <- as.numeric(panel[[term]])
  if (anyNA(normalized$RS) || any(!nzchar(normalized$RS)) || anyNA(normalized$Year)) {
    stop("Region and year identifiers must be complete.", call. = FALSE)
  }
  if (anyDuplicated(normalized[c("RS", "Year")])) {
    stop("panel must contain at most one row per region and year.", call. = FALSE)
  }
  weather_matrix <- as.matrix(normalized[, manifest$Term, drop = FALSE])
  if (any(!is.finite(weather_matrix))) {
    stop("Weather terms must be finite; imputation must be an explicit preprocessing decision.", call. = FALSE)
  }
  normalized <- normalized[order(normalized$Year, normalized$RS), , drop = FALSE]
  rownames(normalized) <- NULL

  equal_weights <- is.null(areas)
  if (equal_weights) {
    normalized_areas <- data.frame(
      RS = sort(unique(normalized$RS)), Area = 1, stringsAsFactors = FALSE
    )
  } else {
    areas <- as.data.frame(areas, stringsAsFactors = FALSE)
    if (!all(c(area_region, area) %in% names(areas))) {
      stop("areas does not contain the configured region and area columns.", call. = FALSE)
    }
    normalized_areas <- data.frame(
      RS = as.character(areas[[area_region]]),
      Area = as.numeric(areas[[area]]),
      stringsAsFactors = FALSE
    )
    if (anyDuplicated(normalized_areas$RS) || any(!is.finite(normalized_areas$Area)) ||
        any(normalized_areas$Area <= 0)) {
      stop("Aggregation areas must be unique, finite, and positive.", call. = FALSE)
    }
    absent <- setdiff(unique(normalized$RS), normalized_areas$RS)
    if (length(absent)) {
      stop("Missing aggregation areas for: ", paste(absent, collapse = ", "), call. = FALSE)
    }
  }

  if (is.null(national_yields)) {
    normalized_national <- data.frame(
      Year = sort(unique(normalized$Year)),
      OfficialNationalYield = NA_real_
    )
  } else {
    national_yields <- as.data.frame(national_yields, stringsAsFactors = FALSE)
    if (!all(c(national_year, national_yield) %in% names(national_yields))) {
      stop("national_yields does not contain the configured columns.", call. = FALSE)
    }
    normalized_national <- data.frame(
      Year = as.integer(national_yields[[national_year]]),
      OfficialNationalYield = as.numeric(national_yields[[national_yield]])
    )
    if (anyNA(normalized_national$Year) || anyDuplicated(normalized_national$Year)) {
      stop("national_yields must contain one complete, unique year per row.", call. = FALSE)
    }
  }
  if (!is.na(harvest_month) && (!harvest_month %in% 1:12)) {
    stop("harvest_month must be an integer from 1 through 12.", call. = FALSE)
  }
  if (is.null(weather_variables)) weather_variables <- unique(manifest$Variable)
  structure(list(
    panel = normalized,
    manifest = manifest,
    areas = normalized_areas,
    national_yields = normalized_national,
    crop = as.character(crop)[1],
    harvest_month = as.integer(harvest_month)[1],
    weather_variables = as.character(weather_variables),
    aggregation = if (equal_weights) "equal" else "supplied_area",
    provenance = provenance
  ), class = "crop_yield_data")
}

#' Read the documented directory-based crop inputs
#'
#' @param data_dir Directory containing `yield.csv`, `crop_areas.csv`, and a
#'   `weather` directory with one `pl_<region>.dat` file per region.
#' @param crop Crop column present in both yield and area files.
#' @param harvest_month Final calendar month in the 12-month agricultural year.
#' @param weather_variables Weather columns to use. All 12 monthly values are
#'   retained; variable selection is never performed by this function.
#'
#' @return An object of class `crop_yield_data`.
#' @export
#' @examples
#' wheat <- read_crop_data(poland_example_path(), "wheat", 7)
#' wheat
read_crop_data <- function(
    data_dir, crop, harvest_month,
    weather_variables = c("SLR", "PCP", "MAX", "MIN", "HMD", "DIF", "TAS")) {
  if (length(data_dir) != 1L || !dir.exists(data_dir)) {
    stop("data_dir must be an existing directory.", call. = FALSE)
  }
  if (length(crop) != 1L || is.na(crop) || !nzchar(crop)) {
    stop("crop must be one non-empty column name.", call. = FALSE)
  }
  harvest_month <- as.integer(harvest_month)
  if (length(harvest_month) != 1L || is.na(harvest_month) || !harvest_month %in% 1:12) {
    stop("harvest_month must be an integer from 1 through 12.", call. = FALSE)
  }
  raw <- cy_load_raw_data(
    normalizePath(data_dir, winslash = "/"), crop,
    as.character(weather_variables), harvest_month
  )
  structure(c(raw, list(
    crop = crop,
    harvest_month = harvest_month,
    weather_variables = as.character(weather_variables),
    aggregation = "supplied_area"
  )), class = "crop_yield_data")
}

#' @export
print.crop_yield_data <- function(x, ...) {
  observed <- x$panel[is.finite(x$panel$.yield), , drop = FALSE]
  cat("<crop_yield_data>\n")
  cat("  crop: ", ifelse(is.na(x$crop), "unspecified", x$crop), "\n", sep = "")
  cat("  regions: ", length(unique(x$panel$RS)), "\n", sep = "")
  cat("  panel years: ", paste(range(x$panel$Year), collapse = "-") , "\n", sep = "")
  if (nrow(observed)) {
    cat("  observed years: ", paste(range(observed$Year), collapse = "-"), "\n", sep = "")
  }
  cat("  weather terms: ", nrow(x$manifest), "\n", sep = "")
  cat("  national weights: ", x$aggregation, "\n", sep = "")
  invisible(x)
}
