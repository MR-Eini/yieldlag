#' Compare paired prediction errors with a year-block bootstrap
#'
#' Resamples consecutive circular blocks of years, retaining all regions in
#' each sampled year. The interval describes uncertainty in a paired RMSE
#' difference on the supplied evaluation period; it is not a guarantee under
#' nonstationarity. Few observed years give weak uncertainty estimates.
#'
#' @param predictions Data frame with `Method`, `RS`, `Year`, `Observed`,
#'   and `Predicted`. Each method must have the same region/year observations.
#' @param reference Reference method name.
#' @param repetitions Number of bootstrap resamples, at least 100.
#' @param block_length Number of consecutive years per block.
#' @param confidence Confidence level between zero and one.
#' @param seed Integer random seed; the caller's random state is preserved.
#' @return A data frame with paired RMSE differences (method minus reference),
#'   percentile limits, observation/year counts, and bootstrap settings.
#' @export
#' @examples
#' p <- expand.grid(RS = c("A", "B"), Year = 2001:2008,
#'                  Method = c("reference", "alternative"))
#' p$Observed <- 10 + p$Year - 2000
#' p$Predicted <- p$Observed + ifelse(p$Method == "reference", 2, 1)
#' compare_crop_errors(p, "reference", repetitions = 100)
compare_crop_errors <- function(predictions, reference, repetitions = 2000L,
    block_length = 2L, confidence = 0.95, seed = 2718L) {
  required <- c("Method", "RS", "Year", "Observed", "Predicted")
  if (!is.data.frame(predictions) || !all(required %in% names(predictions))) {
    stop("predictions must contain Method, RS, Year, Observed, and Predicted.", call. = FALSE)
  }
  scalar_integer <- function(x) is.numeric(x) && length(x) == 1L &&
    is.finite(x) && x == as.integer(x)
  if (!scalar_integer(repetitions) || repetitions < 100L ||
      !scalar_integer(block_length) || block_length < 1L ||
      !scalar_integer(seed) || !is.numeric(confidence) || length(confidence) != 1L ||
      !is.finite(confidence) || confidence <= 0 || confidence >= 1) {
    stop("Invalid bootstrap settings.", call. = FALSE)
  }
  p <- predictions[, required, drop = FALSE]
  if (anyNA(p) || any(!is.finite(p$Observed)) || any(!is.finite(p$Predicted)) ||
      !is.numeric(p$Year) || any(!is.finite(p$Year)) || any(p$Year != as.integer(p$Year)) ||
      anyDuplicated(p[c("Method", "RS", "Year")])) {
    stop("Prediction keys must be unique and predictions finite and complete.", call. = FALSE)
  }
  methods <- unique(as.character(p$Method))
  if (length(reference) != 1L || !reference %in% methods || length(methods) < 2L) {
    stop("reference must identify one of at least two methods.", call. = FALSE)
  }
  baseline <- p[as.character(p$Method) == reference, , drop = FALSE]
  baseline <- baseline[order(baseline$Year, baseline$RS), , drop = FALSE]
  years <- sort(unique(baseline$Year))
  if (length(years) < 3L || block_length > length(years) || any(diff(years) != 1L)) {
    stop("At least three consecutive years are required; block_length cannot exceed them.", call. = FALSE)
  }
  old_seed_exists <- exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
  if (old_seed_exists) old_seed <- get(".Random.seed", envir = .GlobalEnv)
  on.exit(if (old_seed_exists) assign(".Random.seed", old_seed, envir = .GlobalEnv)
    else if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
      rm(".Random.seed", envir = .GlobalEnv), add = TRUE)
  set.seed(seed)
  year_rows <- lapply(years, function(y) which(baseline$Year == y))
  indices <- replicate(repetitions, {
    starts <- sample.int(length(years), ceiling(length(years) / block_length), replace = TRUE)
    sampled <- unlist(lapply(starts, function(s)
      ((s - 1L + seq_len(block_length) - 1L) %% length(years)) + 1L))
    unlist(year_rows[sampled[seq_along(years)]], use.names = FALSE)
  }, simplify = FALSE)
  baseline_error <- (baseline$Predicted - baseline$Observed)^2
  output <- lapply(setdiff(methods, reference), function(method) {
    part <- p[as.character(p$Method) == method, , drop = FALSE]
    part <- part[order(part$Year, part$RS), , drop = FALSE]
    if (!identical(as.character(part$RS), as.character(baseline$RS)) ||
        !identical(as.integer(part$Year), as.integer(baseline$Year)) ||
        !isTRUE(all.equal(part$Observed, baseline$Observed, check.attributes = FALSE))) {
      stop("Methods must have identical paired observations and region/year keys.", call. = FALSE)
    }
    error <- (part$Predicted - part$Observed)^2
    differences <- vapply(indices, function(i)
      sqrt(mean(error[i])) - sqrt(mean(baseline_error[i])), numeric(1))
    limits <- quantile(differences, c((1 - confidence) / 2, (1 + confidence) / 2), names = FALSE)
    data.frame(Method = method, Reference = reference, N = nrow(part), Years = length(years),
      RMSEDifference = sqrt(mean(error)) - sqrt(mean(baseline_error)),
      Lower = limits[1], Upper = limits[2], Confidence = confidence,
      Repetitions = repetitions, BlockLength = block_length, Seed = seed)
  })
  do.call(rbind, output)
}
