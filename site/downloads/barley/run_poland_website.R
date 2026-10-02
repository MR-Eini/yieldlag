#!/usr/bin/env Rscript
# Reproduce the two documented cereal examples using YieldLag 0.2.0.
# Run from the repository root. Outputs are kept under outputs/website_poland.
arguments <- commandArgs(trailingOnly = TRUE)
crop <- if (length(arguments)) arguments[1] else "barley"
endpoints <- c(barley = 6L, wheat = 7L)
if (!crop %in% names(endpoints)) stop("Choose barley or wheat.")
library(yieldlag)
stopifnot(as.character(packageVersion("yieldlag")) == "0.2.0")
config <- crop_model_config(
  methods = crop_model_methods(),
  stress_temperature = "MAX", stress_precipitation = "PCP",
  robust = TRUE
)
data <- read_crop_data(poland_example_path(), crop,
  harvest_month = endpoints[[crop]], weather_variables = config$weather_variables)
output <- file.path("outputs", "website_poland", crop)
if ("--reuse" %in% arguments) {
  comparison <- readRDS(file.path(output, "model_comparison.rds"))
  stopifnot(comparison$package_version == "0.2.0", comparison$crop == crop,
    comparison$last_yield_year == 2018L, comparison$predict_through == 2019L,
    identical(comparison$config, config))
} else {
  comparison <- compare_crop_models(data, config,
    last_yield_year = 2018, predict_through = 2019, verbose = TRUE)
  write_crop_results(comparison, output, overwrite = TRUE)
}
utils::write.csv(data$panel, file.path(output, "input_panel.csv"), row.names = FALSE)
areas <- data$areas
utils::write.csv(areas, file.path(output, "area_weights.csv"), row.names = FALSE)
lookup <- utils::read.csv(file.path(poland_example_path(), "crop_areas.csv"),
  fileEncoding = "UTF-8", check.names = FALSE)[, c("RS", "Region")]
lookup <- lookup[as.character(lookup$RS) %in% unique(data$panel$RS), ]
utils::write.csv(lookup, file.path(output, "region_names.csv"), row.names = FALSE,
  fileEncoding = "UTF-8")
future <- subset(data$panel, Year == 2019)
stress <- get_crop_model(comparison, "stress_lag")
components <- explain_crop_prediction(stress, future)
stopifnot(isTRUE(all.equal(components$Prediction,
  as.numeric(predict(stress, future)), tolerance = 1e-10)))
utils::write.csv(components, file.path(output, "stress_components_2019.csv"), row.names = FALSE)
support <- do.call(rbind, lapply(names(comparison$results), function(method) {
  part <- prediction_support(get_crop_model(comparison, method), future)
  part$Method <- method
  part
}))
utils::write.csv(support, file.path(output, "support_2019.csv"), row.names = FALSE)
metadata <- list(package = "yieldlag", version = comparison$package_version,
  crop = crop, harvest_month = comparison$harvest_month,
  years = comparison$year_split, selected_method = comparison$selected_method,
  selection_rule = comparison$selection_rule, runtime_seconds = comparison$runtime_seconds,
  region_count = length(unique(data$panel$RS)), weather_terms = nrow(data$manifest),
  training_yield_count = sum(data$panel$Year <= 2018 & is.finite(data$panel$.yield)),
  held_out_year = 2019, config = unclass(config),
  selected_parameters = lapply(comparison$results, `[[`, "selected_params"),
  data_sha256_manifest = "inst/extdata/poland/input_sha256.csv",
  source_tag = "v0.2.0", source_commit = "29e1674cda4dcffd8b59d011856cf60951e51d45")
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Website export requires jsonlite.")
jsonlite::write_json(metadata, file.path(output, "metadata.json"),
  auto_unbox = TRUE, pretty = TRUE, digits = 16)
print(comparison)
print(comparison$metrics)
cat("Completed:", crop, "\n")
