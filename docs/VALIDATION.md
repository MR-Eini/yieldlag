# Validation and interpretation

## Chronological design

Observed years are divided into initial history, tuning, and later evaluation.
A prediction for year t uses model coefficients and preprocessing fitted to
observations with years less than t. Hyperparameters are selected from rolling
tuning scores and remain fixed in later evaluation; coefficients and preprocessing
are refitted at each later forecast origin. Automatic selection minimizes
province-year tuning RMSE and does not use evaluation rankings.

The stress-lag climatology, anomaly scale, expanded feature scaling, and regional
effects obey the same training-window rule. Compound mappings are declared by
the user. The ensemble combines requested base estimators using tuning data.

By default, tuning errors are reused for hyperparameter/method selection and
interval calibration. Configure `calibration_years > 0` to reserve years after
tuning and before evaluation for separate interval calibration. Calibration
responses never select method parameters or the automatic method. These
temporally dependent empirical bands carry no distribution-free guarantee.
The later block estimates the selected procedure on this dataset and period.
Once used to guide development, it should be described as a development benchmark.

## Diagnostics

RMSE, MAE, and bias retain the response unit. Bias is prediction minus observation.
Predictive R-squared can be negative; squared correlation does not assess
calibration. Coverage and width describe empirical prediction bands.
Province-year observations share years and regions and are correlated.
Year/block resampling is appropriate when estimating uncertainty for comparisons.
`compare_crop_errors()` resamples paired consecutive circular year blocks,
keeping all regions in each sampled year. It preserves the caller's random state.
Its interval describes RMSE differences on the supplied period; seven annual
blocks remain a small basis for inference.

Prediction support flags marginal weather extrapolation and unseen regions.
Its absence does not establish support of every weather combination.
Decompositions reproduce the fitted equation, not causal or physiological effects.

## Poland example

With a 2018 training cutoff, the default periods are 1999--2005 initial history,
2006--2011 tuning, and 2012--2018 evaluation. Weather through 2019 permits a
retrospective 2019 forecast. National evaluation has seven annual observations.
The example uses fixed area weights and area-weighted provincial observed yields,
rather than independently observed national yields or origin-specific annual areas.

## Synthetic nonlinear example

`synthetic_stress_example()` supplies a fully declared deterministic equation
with asymmetric temperature/precipitation responses and a compound hot-dry term.
A later-period comparison checks that the estimator can recover this kind of
nonlinear signal. This controlled result does not demonstrate superiority on
observed crops or independently validate a new scientific method.

## External evaluation

A scientific comparison should include untouched later data, spatial holdouts,
persistence and trend baselines, uncertainty for paired metric differences,
sensitivity to seasons/grids, and information available at the intended issue date.
Failures and weak crop targets should be reported alongside gains. Operational
forecasting requires weather observations or forecasts actually available at
that date and appropriately time-varying aggregation weights.
