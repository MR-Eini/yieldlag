#!/usr/bin/env Rscript
for(f in list.files("R",pattern="[.]R$",full.names=TRUE)) source(f)
args <- commandArgs(trailingOnly=TRUE)
crop <- if(length(args)) args[1] else "wheat"
data <- read_crop_data("inst/extdata/poland",crop,if(crop=="wheat") 7 else 6,c("MAX","PCP"))
training <- subset(data$panel,Year>=1999 & Year<=2018 & is.finite(.yield))
regions <- sort(unique(training$RS))
folds <- data.frame(RS=regions,Fold=rep(1:4,length.out=length(regions)))
output <- file.path("research/results",paste0("poland_",crop))
write.csv(folds,file.path(output,"spatial_folds.csv"),row.names=FALSE)
grid <- expand.grid(lambda=c(10,100,1000,10000),smooth_ratio=c(0,10,100))
sets <- lapply(seq_len(nrow(grid)),function(i) as.list(grid[i,]))
variants <- list(panel_ridge=sets,
  hierarchical=lapply(seq_len(12),function(i) {
    g<-expand.grid(lambda_global=c(10,100,1000),ratio=c(3,30),smooth_ratio=c(0,10))
    list(lambda_global=g$lambda_global[i],lambda_region=g$lambda_global[i]*g$ratio[i],smooth_ratio=g$smooth_ratio[i])
  }),stress_lag=lapply(sets,function(p) c(p,list(threshold=.75,
    temperature_variable="MAX",precipitation_variable="PCP"))))
predictions <- list(); tuning <- list()
for(fold in 1:4) {
  held <- folds$RS[folds$Fold==fold]
  development <- training[!training$RS %in% held,]
  for(method in names(variants)) {
    cat(crop,fold,method,"\n"); flush.console()
    scores <- lapply(seq_along(variants[[method]]),function(i) {
      p <- cy_rolling_method(development,data$manifest,2005:2008,method,
        variants[[method]][[i]],robust=FALSE)
      data.frame(Fold=fold,Method=method,Candidate=i,
        Parameters=cy_params_string(variants[[method]][[i]]),cy_metrics(p$Observed,p$Predicted))
    })
    scores <- do.call(rbind,scores)
    chosen <- scores$Candidate[order(scores$RMSE,scores$MAE)][1]
    tuning[[paste(fold,method)]] <- scores
    for(year in 2012:2018) {
      train <- subset(development,Year<year)
      test <- subset(training,Year==year & RS %in% held)
      model <- cy_fit_model(method,train,data$manifest,variants[[method]][[chosen]],robust=FALSE)
      p <- cy_predict_model(model,test,use_ar=TRUE)
      predictions[[paste(fold,method,year)]] <- data.frame(Fold=fold,Method=method,
        RS=test$RS,Year=year,Observed=test$.yield,Predicted=p,TrainEnd=max(train$Year),
        UnseenRegion=all(!test$RS %in% model$regions))
    }
  }
  for(year in 2012:2018) {
    train <- subset(development,Year<year)
    test <- subset(training,Year==year & RS %in% held)
    model <- lm(.yield~Year,data=train)
    predictions[[paste(fold,"pooled_trend",year)]] <- data.frame(Fold=fold,Method="pooled_trend",
      RS=test$RS,Year=year,Observed=test$.yield,Predicted=as.numeric(predict(model,test)),
      TrainEnd=max(train$Year),UnseenRegion=TRUE)
  }
}
p <- do.call(rbind,predictions)
write.csv(p,file.path(output,"spatial_predictions.csv"),row.names=FALSE)
write.csv(do.call(rbind,tuning),file.path(output,"spatial_tuning.csv"),row.names=FALSE)
write.csv(do.call(rbind,lapply(split(p,p$Method),function(x)
  cbind(Method=unique(x$Method),cy_metrics(x$Observed,x$Predicted)))),
  file.path(output,"spatial_metrics.csv"),row.names=FALSE)
write.csv(compare_crop_errors(p,"pooled_trend"),file.path(output,"spatial_paired_bootstrap.csv"),row.names=FALSE)
cat("COMPLETE SPATIAL",crop,"\n")
