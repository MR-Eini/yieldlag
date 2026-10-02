# Statistical specification

## Shared estimation

YieldLag models annual regional yield y_it using a standardized time trend,
monthly weather terms, and regional effects. Preprocessing and coefficients are
estimated within each training window. Ridge penalties control coefficient size;
second-difference penalties smooth consecutive seasonal-month coefficients.
Robust fitting uses iteratively reweighted Student-t-style residual weights.
Optional pooled AR(1) correction uses residuals preceding a prediction year.

Baselines are independent regional trends and last-observation persistence.
Panel ridge pools weather slopes; local ridge estimates regional slopes; PCR
estimates training-window principal components; the hierarchical estimator
partially pools regional deviations around a global seasonal response.

## Seasonal stress-lag basis

For variable v, seasonal month m, region i, and training set T:

```text
mu_i,v,m = mean_T(x_i,t,v,m)
s_v,m^2 = sum_T((x_i,t,v,m - mu_i,v,m)^2) / (n_T - number_of_regions)
z_i,t,v,m = (x_i,t,v,m - mu_i,v,m) / s_v,m
L(z) = z
H(z) = max(z - tau, 0)
D(z) = max(-z - tau, 0)
C(z_T, z_P) = H(z_T) * D(z_P)
```

Near-zero scales are replaced by one. For an unseen region, pooled training
means replace regional means; regional effects are zero. This fallback enables
computation but requires separate validation of spatial transfer.

Every declared weather variable receives linear, upper-tail, and lower-tail
terms. Compound terms are optional and require explicit temperature and
precipitation variable mappings. They match calendar month and seasonal position.
A temperature/precipitation pair contributes one product per matched month.
Tau is positive and expressed in units of within-region weather variability.
It is not an absolute temperature or physiological threshold.

Expanded basis columns are centered and scaled within the training set. The
penalized model is

```text
y_it = intercept + b * standardized_year
       + regional_intercept_i + regional_trend_i * standardized_year
       + sum_j(theta_j * standardized_basis_it,j) + error_it
```

The existing panel-ridge solver estimates the coefficients. Each variable/basis
component has its own seasonal second-difference penalty; compound products
are smoothed as a separate component. A common ridge strength and smoothing
ratio control all weather components. Regional intercept and trend penalties
are 0.05 and 0.25 times the weather ridge penalty; the global trend penalty is
0.05 times that penalty. Lambda, smoothing ratio, and tau are tuned on earlier
rolling forecasts. Climatology and basis scaling are refitted inside every
forecast-origin training window.

The basis captures nonlinear associations in monthly climate. It does not
reconstruct daily degree-days, physiological stress, phenology, or irrigation.
The sign of a coefficient is estimated; damage signs are not imposed.

## Prediction interpretation

`explain_crop_prediction()` returns contributions for intercept, trend,
regional effects, linear anomalies, upper/lower tails, hot-dry interaction,
and AR correction. Their sum reproduces `predict()` numerically. Centering
means a tail contribution can be nonzero even when its raw hinge is zero;
the reference is the training basis mean. These are additive statistical
components, not causal attribution or measured crop losses.

`prediction_support()` reports the number of weather terms outside pooled
training minima/maxima, the maximum absolute standardized anomaly, and unseen
region status. Marginal ranges do not diagnose every unsupported multivariate
combination and do not provide a coverage guarantee.

## Ensemble and uncertainty

The ensemble fits non-negative weights summing to one. Shrinkage toward equal
weighting is tuned by leaving out complete tuning years. Base hyperparameters
are themselves chosen using the tuning block, so this is not a fully nested
estimate of model-selection uncertainty. Weights are frozen for later evaluation.

Prediction interval half-widths are empirical tuning-error quantiles. National
half-widths are separately calibrated from national tuning errors. The nominal
80% label describes the calibration target rather than a formal coverage guarantee.

## References

- Schlenker and Roberts (2009), nonlinear weather-yield associations:
  https://doi.org/10.1073/pnas.0906865106.
- Gasparrini, Armstrong, and Kenward (2010), distributed lag nonlinear models:
  https://doi.org/10.1002/sim.3940.

YieldLag uses penalized monthly hinge/product features. It does not implement
the daily exposure bins of the first study or the full cross-basis machinery
of the second. These established ideas motivate the implementation; they are
not claims that this package introduces nonlinear crop response for the first time.
