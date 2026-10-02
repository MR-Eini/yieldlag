#!/usr/bin/env Rscript
# Reuse completed cached fits, add stacking, reserved-year scoring and native ABSOLUT.
source("research/run_study.R")
base <- c("trend","persistence","panel_ridge","local_ridge","pcr","hierarchical","stress_lag")
keys <- results[[base[1]]]$tuning_prediction
matrix_for <- function(slot) {
  first <- results[[base[1]]][[slot]]
  target <- paste(first$RS,first$Year)
  sapply(base,function(n) {
    p <- results[[n]][[slot]]
    p$Predicted[match(target,paste(p$RS,p$Year))]
  })
}
grid <- c(0,1,10,100,1000,10000)
stack_scores <- lapply(grid,function(lambda) {
  predicted <- rep(NA_real_,nrow(keys))
  x <- matrix_for("tuning_prediction")
  for(year in sort(unique(keys$Year))) {
    held <- keys$Year==year
    weights <- cy_fit_simplex_weights(x[!held,,drop=FALSE],keys$Observed[!held],shrinkage=lambda)
    predicted[held] <- as.numeric(x[held,,drop=FALSE]%*%weights)
  }
  data.frame(Shrinkage=lambda,cy_metrics(keys$Observed,predicted))
})
stack_scores <- do.call(rbind,stack_scores)
lambda <- stack_scores$Shrinkage[order(stack_scores$RMSE,stack_scores$MAE)][1]
weights <- cy_fit_simplex_weights(matrix_for("tuning_prediction"),keys$Observed,shrinkage=lambda)
stack <- list(parameters=c(list(shrinkage=lambda),as.list(weights)))
for(slot in c("tuning_prediction","calibration","evaluation")) {
  p <- results[[base[1]]][[slot]]
  p$Method <- "ensemble"
  p$Predicted <- as.numeric(matrix_for(slot)%*%weights)
  stack[[slot]] <- p
}
half <- cy_empirical_half_width(stack$calibration$Observed,stack$calibration$Predicted)
for(slot in c("tuning_prediction","calibration","evaluation")) {
  stack[[slot]]$Lower80 <- stack[[slot]]$Predicted-half
  stack[[slot]]$Upper80 <- stack[[slot]]$Predicted+half
}
write.csv(data.frame(Method=names(weights),Weight=weights),file.path(output,"ensemble_weights.csv"),row.names=FALSE)
write.csv(stack_scores,file.path(output,"ensemble_tuning.csv"),row.names=FALSE)
eval <- rbind(eval,stack$evaluation)
write.csv(eval,file.path(output,"evaluation_predictions.csv"),row.names=FALSE)
write.csv(compare_crop_errors(eval,"hierarchical"),file.path(output,"paired_bootstrap_block2.csv"),row.names=FALSE)
write.csv(cbind(Method="ensemble",yield_metrics(stack$evaluation$Observed,stack$evaluation$Predicted,
  stack$evaluation$Lower80,stack$evaluation$Upper80)),file.path(output,"ensemble_metrics.csv"),row.names=FALSE)

# Apply previously tuning-selected settings to 2019, using only <=2018 responses.
future <- subset(data$panel,Year==2019 & is.finite(.yield))
future_predictions <- list()
for(name in names(variants)) {
  variant <- variants[[name]]; params <- results[[name]]$parameters
  if(variant$method %in% c("gam","forest")) {
    fitted <- external_fit(variant$method,training,params)
    predicted <- external_predict(variant$method,fitted,future)
  } else {
    fitted <- cy_fit_model(variant$method,training,data$manifest,params,variant$robust)
    predicted <- cy_predict_model(fitted,future,use_ar=variant$ar)
  }
  future_predictions[[name]] <- data.frame(Method=name,RS=future$RS,Year=2019,
    Observed=future$.yield,Predicted=predicted,TrainEnd=2018)
}
future_matrix <- sapply(base,function(n) future_predictions[[n]]$Predicted)
future_predictions$ensemble <- data.frame(Method="ensemble",RS=future$RS,Year=2019,
  Observed=future$.yield,Predicted=as.numeric(future_matrix%*%weights),TrainEnd=2018)
write.csv(do.call(rbind,future_predictions),file.path(output,"reserved_2019_predictions.csv"),row.names=FALSE)
write.csv(do.call(rbind,lapply(future_predictions,function(p)
  cbind(Method=unique(p$Method),cy_metrics(p$Observed,p$Predicted)))),
  file.path(output,"reserved_2019_metrics.csv"),row.names=FALSE)

if(startsWith(case,"poland_")) {
  paths <- file.path("research/external/absolut-runs",paste0(case,"-",2016:2018),"absolut-412-output.dat")
  if(all(file.exists(paths))) {
    native <- do.call(rbind,lapply(seq_along(paths),function(i) {
      p <- read.table(paths[i],header=TRUE)
      p <- subset(p,Year==2015+i & is.finite(Predn))
      actual <- subset(data$panel,Year==2015+i,c("RS","Year",".yield"))
      p$RS <- as.character(p$RS)
      p <- merge(p,actual,by=c("RS","Year"))
      data.frame(Method="ABSOLUT_v1.2",RS=p$RS,Year=p$Year,
        Observed=p$.yield,Predicted=p$Predn,TrainEnd=2014+i)
    }))
    common <- subset(eval,Year>=2016,c("Method","RS","Year","Observed","Predicted","TrainEnd"))
    comparison <- rbind(common,native)
    write.csv(comparison,file.path(output,"absolut_comparison_predictions.csv"),row.names=FALSE)
    write.csv(do.call(rbind,lapply(split(comparison,comparison$Method),function(p)
      cbind(Method=unique(p$Method),cy_metrics(p$Observed,p$Predicted)))),
      file.path(output,"absolut_comparison_metrics.csv"),row.names=FALSE)
    write.csv(compare_crop_errors(comparison,"ABSOLUT_v1.2",block_length=1),
      file.path(output,"absolut_paired_bootstrap.csv"),row.names=FALSE)
    for(year in 2016:2018) file.copy(file.path("research/external/absolut-runs",
      paste0(case,"-",year),"adapter_manifest.json"),
      file.path(output,paste0("absolut_manifest_",year,".json")),overwrite=TRUE)
  }
}
cat("COMPLETE AUGMENTED",case,"\n")
