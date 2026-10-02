#!/usr/bin/env Rscript
# Run from repository root. Package source is loaded without editing installed libraries.
for (f in list.files("R", pattern = "[.]R$", full.names = TRUE)) source(f)
args <- commandArgs(trailingOnly = TRUE)
case <- if (length(args)) args[1] else "poland_wheat"
dir.create("research/results", recursive = TRUE, showWarnings = FALSE)
output <- file.path("research/results", case)
dir.create(output, recursive = TRUE, showWarnings = FALSE)
config <- crop_model_config(initial_fraction = .30, tuning_fraction = .20,
  calibration_years = 3, weather_variables = c("MAX", "PCP"), robust = FALSE,
  stress_temperature = "MAX", stress_precipitation = "PCP")
config$grids$panel_ridge <- config$grids$local_ridge <-
  list(lambda = c(10,100,1000,10000), smooth_ratio = c(0,10,100))
config$grids$stress_lag <- c(config$grids$panel_ridge, list(threshold = .75))
config$grids$hierarchical <- list(lambda_global = c(10,100,1000),
  lambda_region = c(30,300), smooth_ratio = c(0,10))

german_data <- function(crop, harvest) {
  raw <- "research/external/raw"
  yields <- read.csv(file.path(raw,"yield-indat.csv"), check.names = FALSE)
  yields <- yields[!is.na(yields$RS) & yields$RS > 999, c("RS","Year",crop)]
  names(yields)[3] <- ".yield"
  initial <- subset(yields, Year <= 2004 & is.finite(.yield))
  counts <- table(initial$RS)
  eligible <- names(counts[counts >= 5])
  manifest <- cy_build_manifest(c("MAX","PCP"), harvest)
  files <- list.files(file.path(raw,"weather/DistrictWeather"), full.names = TRUE)
  weather <- lapply(files, function(f) {
    id <- as.character(as.integer(sub("^dw_([0-9]+)[.]dat$","\\1",basename(f))))
    if (!id %in% eligible) return(NULL)
    w <- read.table(f, header = TRUE)
    w$MAX <- w$tasmax; w$PCP <- w$pr
    cy_weather_to_years(w, id, c("MAX","PCP"), harvest, manifest)
  })
  panel <- merge(do.call(rbind,weather), yields, by = c("RS","Year"), all.x = TRUE)
  prepare_crop_data(panel, manifest, crop = crop, harvest_month = harvest,
    provenance = list(doi = "10.5281/zenodo.4468691", country = "Germany",
      terms = "CC-BY-4.0 and agricultural attribution dl-de/by-2-0",
      aggregation = "equal district weights; not national agricultural yield"))
}
if (startsWith(case,"germany_")) {
  barley <- grepl("barley",case)
  data <- german_data(if (barley) "Winter.barley" else "Winter.wheat", if(barley) 6 else 7)
} else {
  barley <- grepl("barley",case)
  data <- read_crop_data("inst/extdata/poland", if(barley) "barley" else "wheat",
    if(barley) 6 else 7, c("MAX","PCP"))
  data$panel <- subset(data$panel, Year >= 1999)
}
training <- subset(data$panel, Year <= 2018 & is.finite(.yield))
split <- list(initial=1999:2004, tuning=2005:2008, calibration=2009:2011,
  evaluation=2012:2018)
prediction_panel <- subset(data$panel, Year %in% 1999:2019)
write.csv(data.frame(RS = sort(unique(training$RS))), file.path(output,"regions.csv"), row.names=FALSE)
saveRDS(data, file.path(output,"prepared_data.rds"))

base_grids <- function(method) {
  if (method == "hierarchical") {
    g <- expand.grid(lambda_global=c(10,100,1000), ratio=c(3,30), smooth_ratio=c(0,10))
    return(lapply(seq_len(nrow(g)),function(i) list(lambda_global=g$lambda_global[i],
      lambda_region=g$lambda_global[i]*g$ratio[i],smooth_ratio=g$smooth_ratio[i])))
  }
  cy_parameter_sets(method, unclass(config))
}
variants <- list()
for (m in c("trend","persistence","panel_ridge","local_ridge","pcr","hierarchical","stress_lag"))
  variants[[m]] <- list(method=m, grid=base_grids(m), robust=FALSE, ar=TRUE)
stress_variant <- function(components, smooth=NULL, regional=TRUE, threshold=.75, robust=FALSE) {
  g <- expand.grid(lambda=c(10,100,1000,10000),smooth_ratio=if(is.null(smooth)) c(0,10,100) else smooth)
  list(method="stress_lag", robust=robust, ar=TRUE,
    grid=lapply(seq_len(nrow(g)),function(i) list(lambda=g$lambda[i],smooth_ratio=g$smooth_ratio[i],
      threshold=threshold, temperature_variable="MAX",precipitation_variable="PCP",
      components=components, regional_effects=regional)))
}
all_components <- c("linear","upper_tail","lower_tail","compound_hot_dry")
variants$anomaly_linear <- stress_variant("linear")
variants$anomaly_tails <- stress_variant(all_components[1:3])
variants$stress_unsmoothed <- stress_variant(all_components,smooth=0)
variants$stress_no_region <- stress_variant(all_components,regional=FALSE)
# Additional sensitivities use Poland only; the German cases have all primary comparators/ablations.
if (startsWith(case,"poland_")) {
  for (threshold in c(.5,1,1.5))
    variants[[paste0("threshold_",threshold)]] <- stress_variant(all_components,threshold=threshold)
  variants$stress_robust <- stress_variant(all_components,robust=TRUE)
}

aggregate_windows <- function(panel, manifest) {
  out <- data.frame(.yield=panel$.yield, Year=panel$Year, RS=as.character(panel$RS))
  for (variable in c("MAX","PCP")) for (window in 1:3) {
    terms <- manifest$Term[manifest$Variable == variable &
      manifest$AgriculturalPosition %in% ((window-1)*4+1:4)]
    out[[paste0(variable,"_w",window)]] <- rowMeans(panel[,terms,drop=FALSE])
  }
  out
}
external_fit <- function(method, train, params) {
  if (method == "gam") {
    transformed <- aggregate_windows(train,data$manifest)
    transformed$Year <- transformed$Year - 1999
    transformed$RS <- factor(transformed$RS)
    formula <- as.formula(paste(".yield ~ Year + RS + RS:Year +",
      paste(sprintf("s(%s, k=4)",grep("_w",names(transformed),value=TRUE)),collapse=" + ")))
    # Bind the mgcv smooth constructor in the formula environment.
    s <- mgcv::s
    if(startsWith(case,"germany_")) return(mgcv::bam(formula,
      data=transformed,method="fREML",discrete=TRUE,nthreads=2,gamma=params$gamma))
    return(mgcv::gam(formula, data=transformed, method="REML", gamma=params$gamma))
  }
  features <- train[,c(".yield","Year","RS",data$manifest$Term)]
  features$RS <- factor(features$RS)
  ranger::ranger(.yield ~ ., data=features, num.trees=500,
    mtry=params$mtry, min.node.size=params$node, seed=2718, num.threads=1)
}
external_predict <- function(method,model,test) {
  if(method=="gam") {
    transformed <- aggregate_windows(test,data$manifest)
    transformed$Year <- transformed$Year - 1999
    transformed$RS <- factor(transformed$RS, levels=model$xlevels$RS)
    return(as.numeric(predict(model,newdata=transformed)))
  }
  features <- test[,c("Year","RS",data$manifest$Term)]
  features$RS <- factor(features$RS)
  as.numeric(predict(model, data=features, num.threads=1)$predictions)
}
variants$gam <- list(method="gam",grid=lapply(c(1,1.4,2),function(x) list(gamma=x)),robust=FALSE,ar=FALSE)
forest_grid <- expand.grid(mtry=c(4,8,16),node=c(5,15,30))
variants$random_forest <- list(method="forest",grid=lapply(seq_len(nrow(forest_grid)),
  function(i) as.list(forest_grid[i,])),robust=FALSE,ar=FALSE)

rolling <- function(variant,params,years,held=NULL,ar=variant$ar) {
  rows <- lapply(years,function(year) {
    train <- subset(training, Year < year)
    test <- subset(training, Year == year)
    if(!is.null(held)) { train <- train[!train$RS %in% held,]; test <- test[test$RS %in% held,] }
    if(!nrow(test)) return(NULL)
    if(variant$method %in% c("gam","forest")) {
      model <- external_fit(variant$method,train,params)
      prediction <- external_predict(variant$method,model,test)
    } else {
      model <- cy_fit_model(variant$method,train,data$manifest,params,variant$robust)
      prediction <- cy_predict_model(model,test,use_ar=ar)
    }
    data.frame(RS=test$RS,Year=year,Observed=test$.yield,Predicted=prediction,
      TrainEnd=max(train$Year),TrainingRegions=length(unique(train$RS)))
  })
  do.call(rbind,rows)
}
results <- list(); tuning_tables <- list(); runtimes <- list()
for (name in names(variants)) {
  cat(case, name, "\n"); flush.console()
  cache <- file.path(output,paste0(name,".rds"))
  if(file.exists(cache)) { results[[name]] <- readRDS(cache); next }
  start <- proc.time()[["elapsed"]]
  variant <- variants[[name]]
  scored <- lapply(seq_along(variant$grid),function(i) {
    p <- rolling(variant,variant$grid[[i]],split$tuning)
    data.frame(Candidate=i,Parameters=cy_params_string(variant$grid[[i]]),
      cy_metrics(p$Observed,p$Predicted))
  })
  scored <- do.call(rbind,scored)
  selected <- scored$Candidate[order(scored$RMSE,scored$MAE)][1]
  params <- variant$grid[[selected]]
  tuned <- rolling(variant,params,split$tuning)
  cal <- rolling(variant,params,split$calibration)
  eval <- rolling(variant,params,split$evaluation)
  half <- cy_empirical_half_width(cal$Observed,cal$Predicted)
  for (phase in c("tuned","cal","eval")) {
    p <- get(phase); p$Method <- name
    p$Lower80 <- p$Predicted-half; p$Upper80 <- p$Predicted+half
    p$Phase <- switch(phase,tuned="tuning",cal="calibration",eval="evaluation")
    assign(phase,p)
  }
  ar_off <- if(variant$method %in% c("gam","forest","persistence")) eval else {
    p <- rolling(variant,params,split$evaluation,ar=FALSE)
    p$Method <- paste0(name,"_no_ar"); p
  }
  result <- list(parameters=params,tuning=scored,tuning_prediction=tuned,calibration=cal,
    evaluation=eval,ar_off=ar_off,half=half,seconds=proc.time()[["elapsed"]]-start,
    fits=length(variant$grid)*length(split$tuning)+length(split$tuning)+
      length(split$calibration)+length(split$evaluation))
  saveRDS(result,cache); results[[name]] <- result
}
eval <- do.call(rbind,lapply(results,`[[`,"evaluation"))
write.csv(eval,file.path(output,"evaluation_predictions.csv"),row.names=FALSE)
write.csv(do.call(rbind,lapply(results,`[[`,"calibration")),file.path(output,"calibration_predictions.csv"),row.names=FALSE)
write.csv(do.call(rbind,lapply(names(results),function(n)
  cbind(Method=n,results[[n]]$tuning))),file.path(output,"tuning_candidates.csv"),row.names=FALSE)
write.csv(do.call(rbind,lapply(names(results),function(n) data.frame(Method=n,
  Parameters=cy_params_string(results[[n]]$parameters),Seconds=results[[n]]$seconds,
  Candidates=nrow(results[[n]]$tuning),Fits=results[[n]]$fits))),
  file.path(output,"selected_parameters.csv"),row.names=FALSE)
metrics <- do.call(rbind,lapply(split(eval,eval$Method),function(p) {
  m <- yield_metrics(p$Observed,p$Predicted,p$Lower80,p$Upper80)
  trend <- results$trend$evaluation
  key <- paste(p$RS,p$Year); idx <- match(key,paste(trend$RS,trend$Year))
  m$TrendRelativeSkill <- 1-sum((p$Observed-p$Predicted)^2)/sum((trend$Observed[idx]-trend$Predicted[idx])^2)
  centered <- p$Observed-ave(p$Observed,p$RS,FUN=mean)
  m$WithinRegionR2 <- 1-sum((p$Observed-p$Predicted)^2)/sum(centered^2)
  m$IntervalScore80 <- mean((p$Upper80-p$Lower80)+10*pmax(p$Lower80-p$Observed,0)+10*pmax(p$Observed-p$Upper80,0))
  cbind(Method=unique(p$Method),m)
}))
write.csv(metrics,file.path(output,"metrics.csv"),row.names=FALSE)
for (block in 1:3) write.csv(compare_crop_errors(eval,"hierarchical",block_length=block),
  file.path(output,paste0("paired_bootstrap_block",block,".csv")),row.names=FALSE)
intervals <- do.call(rbind,lapply(names(results),function(n) {
  r <- results[[n]]; p <- r$evaluation
  ht <- cy_empirical_half_width(r$tuning_prediction$Observed,r$tuning_prediction$Predicted)
  do.call(rbind,lapply(c("separate_calibration","tuning_reuse"),function(mode) {
    h <- if(mode=="separate_calibration") r$half else ht
    data.frame(Method=n,Calibration=mode,CalibrationYears=if(mode=="separate_calibration") 3 else 4,
      HalfWidth=h,Coverage=mean(abs(p$Observed-p$Predicted)<=h),MeanWidth=2*h,
      IntervalScore80=mean(2*h+10*pmax(abs(p$Observed-p$Predicted)-h,0)))
  }))
}))
write.csv(intervals,file.path(output,"interval_comparison.csv"),row.names=FALSE)
no_ar <- do.call(rbind,lapply(names(results),function(n) {
  p <- results[[n]]$ar_off
  cbind(Method=n,cy_metrics(p$Observed,p$Predicted))
}))
write.csv(no_ar,file.path(output,"ar_off_metrics.csv"),row.names=FALSE)
writeLines(capture.output(sessionInfo()),file.path(output,"session_info.txt"))
dependencies <- c("mgcv", "ranger", "foreach", "leaps", "jsonlite")
write.csv(data.frame(Package=c("R",dependencies), Version=c(as.character(getRversion()),
  vapply(dependencies,function(p) as.character(utils::packageVersion(p)),character(1)))),
  file.path(output,"dependency_versions.csv"),row.names=FALSE)
saveRDS(results,file.path(output,"study_results.rds"))
cat("COMPLETE",case,"\n")
