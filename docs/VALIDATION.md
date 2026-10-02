# Validation design and interpretation

## Reference split

- Initial history: 1999-2005.
- Hyperparameter and interval calibration: rolling forecasts for 2006-2011.
- Later evaluation: rolling forecasts for 2012-2018.
- Final fit: all observed province-years from 1999-2018.
- Retrospective forecast: 2019 weather, with the 2019 yield withheld from fit.

For a validation year `t`, every scaler, decomposition, coefficient, residual
correction, and model fit uses years strictly less than `t`. Hyperparameters
and ensemble shrinkage are selected before the later evaluation period.

## Reported metrics

- RMSE and MAE retain the yield unit (dt/ha).
- Bias is predicted minus observed.
- `R2` is predictive R-squared against the evaluation mean and may be negative.
- `Cor_R2` is squared correlation and does not measure calibration.
- Coverage and mean width describe the empirically calibrated 80% bands.

Province-year metrics use 112 forecasts (16 provinces x 7 years). These rows
are correlated within province and year; 112 is not an independent sample
size. National metrics use seven area-weighted forecasts and are therefore
highly uncertain.

## What the reference result establishes

Historical results demonstrate the workflow on a particular chronological split.
They do not establish superiority outside Poland, outside a tested crop, after
2019, or beyond the training climate support. The public example removes the
supplied unweighted national-mean rows and instead scores national predictions
against area-weighted observed provincial yields. Historical national metrics
used another comparator and are not directly comparable to this release.

## Publication-grade next validation

Before making a strong standalone-model claim:

1. Archive an independent later period not used during method development.
2. Repeat evaluation for multiple crops and report failures as well as gains.
3. Use blocked bootstrap or year-level resampling for metric uncertainty.
4. Assess spatial transfer by holding out complete provinces.
5. Compare against a naive last-year baseline and suitable published methods.
6. Test coefficient and ranking sensitivity to tuning-window and grid choices.
7. Document weather-variable units, aggregation, quality control, and licenses.

Fixed study area weights are not annual weights available at each forecast
origin. National aggregation is a retrospective benchmark. Complete harvest-year
weather also makes the one-year example retrospective, rather than an early
forecast issued before those weather observations were available.

The current 2012-2018 block was not used to select fitted hyperparameters, but
once its results guide future model redesign it should be regarded as a
development benchmark. New data are then needed for a genuinely untouched
confirmatory test.
