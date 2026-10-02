#' cropyieldmodel: transparent regional crop-yield modelling
#'
#' The package supplies a deterministic, base-R modelling engine and a
#' high-level workflow that keeps tuning, later evaluation, final fitting, and
#' artifact export separate. See [crop_model_config()], [read_crop_data()],
#' [compare_crop_models()], and [write_crop_results()] for the main workflow.
#'
#' @keywords internal
#' @importFrom grDevices dev.off png
#' @importFrom graphics abline axis barplot legend lines mtext par plot.new
#' @importFrom stats ave coef cor lm median predict quantile sd setNames weighted.mean
#' @importFrom utils capture.output read.csv read.table
"_PACKAGE"

#' Available statistical crop-yield methods
#'
#' @return A character vector of method identifiers accepted by
#'   [crop_model_config()] and [fit_crop_model()].
#' @export
#' @examples
#' crop_model_methods()
crop_model_methods <- function() {
  c(
    "trend", "persistence", "panel_ridge", "local_ridge", "pcr",
    "hierarchical", "ensemble"
  )
}

cy_base_methods <- function() setdiff(crop_model_methods(), "ensemble")

cy_default_grids <- function() {
  list(
    panel_ridge = list(
      lambda = c(1, 10, 100, 1000),
      smooth_ratio = c(0, 10, 100)
    ),
    local_ridge = list(
      lambda = c(10, 100, 1000),
      smooth_ratio = c(0, 10, 100)
    ),
    pcr = list(components = c(3L, 5L, 10L, 15L, 20L)),
    hierarchical = list(
      lambda_global = c(10, 100, 1000),
      lambda_region = c(30, 300, 3000),
      smooth_ratio = c(0, 10, 100)
    ),
    ensemble = list(shrinkage = c(0, 1, 10, 100, 1000, 10000))
  )
}

#' Configure a crop-yield model comparison
#'
#' @param methods Character vector. `persistence` is the last-observation
#'   benchmark. `ensemble` is learned from the requested base methods. If it is
#'   requested alone, all base methods are fitted.
#' @param weather_variables Monthly weather variables used when raw files are
#'   read. Drought indices are not included by default.
#' @param initial_fraction Fraction of observed years assigned to the initial
#'   history before rolling hyperparameter tuning.
#' @param tuning_fraction Fraction of observed years assigned to rolling
#'   tuning and interval calibration. Remaining years form the later
#'   evaluation block.
#' @param grids Named list of hyperparameter grids. `NULL` uses the documented
#'   package defaults.
#' @param interval_level Coverage level for empirical prediction intervals.
#'   Version 0.1.0 uses 0.80 so interval columns and diagnostics remain
#'   unambiguous.
#' @param robust Whether to use robust iteratively reweighted fitting where
#'   supported.
#'
#' @return An object of class `crop_model_config`.
#' @export
#' @examples
#' crop_model_config(methods = c("trend", "hierarchical"))
crop_model_config <- function(
    methods = crop_model_methods(),
    weather_variables = c("SLR", "PCP", "MAX", "MIN", "HMD", "DIF", "TAS"),
    initial_fraction = 0.35,
    tuning_fraction = 0.30,
    grids = NULL,
    interval_level = 0.80,
    robust = TRUE) {
  methods <- unique(as.character(methods))
  unknown <- setdiff(methods, crop_model_methods())
  if (!length(methods)) stop("At least one method is required.", call. = FALSE)
  if (length(unknown)) {
    stop("Unknown methods: ", paste(unknown, collapse = ", "), call. = FALSE)
  }
  weather_variables <- unique(as.character(weather_variables))
  if (!length(weather_variables) || anyNA(weather_variables) ||
      any(!nzchar(weather_variables))) {
    stop("weather_variables must contain non-empty names.", call. = FALSE)
  }
  if (!is.numeric(initial_fraction) || length(initial_fraction) != 1L ||
      !is.finite(initial_fraction) || initial_fraction <= 0 || initial_fraction >= 1) {
    stop("initial_fraction must be strictly between zero and one.", call. = FALSE)
  }
  if (!is.numeric(tuning_fraction) || length(tuning_fraction) != 1L ||
      !is.finite(tuning_fraction) || tuning_fraction <= 0 || tuning_fraction >= 1) {
    stop("tuning_fraction must be strictly between zero and one.", call. = FALSE)
  }
  if (initial_fraction + tuning_fraction >= 0.9) {
    stop("The fractions must leave at least 10% of years for evaluation.", call. = FALSE)
  }
  if (!is.numeric(interval_level) || length(interval_level) != 1L ||
      !is.finite(interval_level) || !isTRUE(all.equal(as.numeric(interval_level), 0.80))) {
    stop("Version 0.1.0 supports interval_level = 0.80.", call. = FALSE)
  }
  if (is.null(grids)) grids <- cy_default_grids()
  grid_methods <- methods
  if (identical(methods, "ensemble")) grid_methods <- c(cy_base_methods(), "ensemble")
  required_grids <- intersect(
    cy_base_methods(), setdiff(grid_methods, c("trend", "persistence"))
  )
  if ("ensemble" %in% grid_methods) required_grids <- union(required_grids, "ensemble")
  missing_grids <- setdiff(required_grids, names(grids))
  if (length(missing_grids)) {
    stop("Missing hyperparameter grids: ", paste(missing_grids, collapse = ", "), call. = FALSE)
  }
  structure(list(
    methods = methods,
    weather_variables = weather_variables,
    initial_fraction = as.numeric(initial_fraction),
    tuning_fraction = as.numeric(tuning_fraction),
    grids = grids,
    interval_level = as.numeric(interval_level),
    robust = isTRUE(robust)
  ), class = "crop_model_config")
}

#' @export
print.crop_model_config <- function(x, ...) {
  cat("<crop_model_config>\n")
  cat("  methods: ", paste(x$methods, collapse = ", "), "\n", sep = "")
  cat("  weather: ", paste(x$weather_variables, collapse = ", "), "\n", sep = "")
  cat("  split fractions: initial=", x$initial_fraction,
      ", tuning=", x$tuning_fraction, "\n", sep = "")
  cat("  interval level: ", x$interval_level, "\n", sep = "")
  invisible(x)
}

#' Path to the bundled Poland case-study inputs
#'
#' The files are included so the workflow can be exercised from an installed
#' package. See `DATA_LICENSE.md` in this directory for source terms and known
#' provenance gaps. The code license does not apply to provider data.
#'
#' @return A normalized directory path.
#' @export
#' @examples
#' list.files(poland_example_path())
poland_example_path <- function() {
  path <- system.file("extdata", "poland", package = "cropyieldmodel")
  if (!nzchar(path)) {
    candidate <- file.path("inst", "extdata", "poland")
    if (dir.exists(candidate)) path <- normalizePath(candidate, winslash = "/")
  }
  if (!nzchar(path) || !dir.exists(path)) {
    stop("Bundled Poland example data were not found.", call. = FALSE)
  }
  normalizePath(path, winslash = "/")
}
