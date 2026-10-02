# Validation splits, performance metrics, and national aggregation.

cy_metrics <- function(observed, predicted) {
  if (length(observed) != length(predicted)) {
    stop("observed and predicted must have the same length.", call. = FALSE)
  }
  keep <- is.finite(observed) & is.finite(predicted)
  observed <- observed[keep]
  predicted <- predicted[keep]
  if (!length(observed)) {
    return(data.frame(N = 0, RMSE = NA, MAE = NA, Bias = NA, R2 = NA, Cor_R2 = NA))
  }
  error <- predicted - observed
  sst <- sum((observed - mean(observed))^2)
  correlation <- if (length(observed) > 1L) cor(observed, predicted) else NA_real_
  data.frame(
    N = length(observed),
    RMSE = sqrt(mean(error^2)),
    MAE = mean(abs(error)),
    Bias = mean(error),
    R2 = if (sst > 0) 1 - sum(error^2) / sst else NA_real_,
    Cor_R2 = correlation^2
  )
}

cy_add_interval_metrics <- function(metrics, predictions) {
  metrics$Coverage80 <- mean(
    predictions$Observed >= predictions$Lower80 &
      predictions$Observed <= predictions$Upper80,
    na.rm = TRUE
  )
  metrics$MeanWidth80 <- mean(predictions$Upper80 - predictions$Lower80, na.rm = TRUE)
  metrics
}

cy_split_years <- function(training_years, initial_fraction, tuning_fraction) {
  years <- sort(unique(training_years))
  initial_count <- max(6L, floor(initial_fraction * length(years)))
  tuning_count <- max(4L, floor(tuning_fraction * length(years)))
  tuning_end <- min(length(years) - 2L, initial_count + tuning_count)
  if (tuning_end - initial_count < 4L) {
    stop("The configured split must leave at least four tuning years and two evaluation years.",
      call. = FALSE)
  }
  list(
    initial = years[seq_len(initial_count)],
    tuning = years[(initial_count + 1L):tuning_end],
    evaluation = years[(tuning_end + 1L):length(years)]
  )
}

cy_aggregate_national <- function(predictions, areas, national_yields) {
  joined <- merge(predictions, areas, by = "RS", all.x = TRUE)
  result <- lapply(sort(unique(joined$Year)), function(year) {
    part <- joined[joined$Year == year & is.finite(joined$Area), , drop = FALSE]
    observed <- is.finite(part$Observed)
    data.frame(
      Method = unique(part$Method)[1],
      Phase = if ("Phase" %in% names(part)) unique(part$Phase)[1] else "final",
      Year = year,
      ObservedWeighted = if (any(observed)) {
        weighted.mean(part$Observed[observed], part$Area[observed])
      } else NA_real_,
      PredictedWeighted = weighted.mean(part$Predicted, part$Area, na.rm = TRUE),
      Lower80Weighted = weighted.mean(part$Lower80, part$Area, na.rm = TRUE),
      Upper80Weighted = weighted.mean(part$Upper80, part$Area, na.rm = TRUE)
    )
  })
  result <- do.call(rbind, result)
  result <- merge(result, national_yields, by = "Year", all.x = TRUE)
  result[order(result$Method, result$Year), , drop = FALSE]
}

cy_national_observed <- function(national_predictions) {
  ifelse(
    is.finite(national_predictions$OfficialNationalYield),
    national_predictions$OfficialNationalYield,
    national_predictions$ObservedWeighted
  )
}
