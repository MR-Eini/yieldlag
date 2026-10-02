#!/usr/bin/env Rscript
.libPaths(c(file.path(getwd(),".repro-library"),.libPaths()))
for(f in list.files("R",pattern="[.]R$",full.names=TRUE)) source(f)
args <- commandArgs(trailingOnly=TRUE)
crop <- if(length(args)) args[1] else "wheat"
output <- file.path("research/results",paste0("poland_",crop))
config <- crop_model_config(methods=c("trend","panel_ridge","hierarchical","stress_lag"),
  initial_fraction=.3,tuning_fraction=.2,calibration_years=3,robust=FALSE,
  stress_temperature="MAX",stress_precipitation="PCP")
for(mode in c("full_weather","six_month_season")) {
  cat(crop,mode,"\n"); flush.console()
  variables <- if(mode=="full_weather") config$weather_variables else c("MAX","PCP")
  data <- read_crop_data("inst/extdata/poland",crop,if(crop=="wheat") 7 else 6,variables)
  data$panel <- subset(data$panel,Year>=1999)
  if(mode=="six_month_season") {
    manifest <- subset(data$manifest,AgriculturalPosition>6)
    manifest$AgriculturalPosition <- manifest$AgriculturalPosition-6L
    data <- prepare_crop_data(data$panel,manifest,areas=data$areas,crop=crop,
      harvest_month=data$harvest_month,provenance=list(season="last six agricultural months"))
  }
  result <- compare_crop_models(data,config,2018,2019,verbose=FALSE)
  write.csv(result$metrics,file.path(output,paste0(mode,"_metrics.csv")),row.names=FALSE)
  write.csv(result$province_cv_predictions,file.path(output,paste0(mode,"_predictions.csv")),row.names=FALSE)
  write.csv(do.call(rbind,lapply(result$results,function(x) x$tuning_table)),
    file.path(output,paste0(mode,"_tuning.csv")),row.names=FALSE)
}
cat("COMPLETE SENSITIVITY",crop,"\n")
