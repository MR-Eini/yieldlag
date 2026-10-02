# Statistical methods

Let `y_it` be yield in province `i` and harvest year `t`, and let `x_it` be the
standardized 84-term monthly weather vector. Standardization is fitted within
each training window, so future observations cannot influence preprocessing.

## Shared components

- A standardized linear time trend represents gradual technological and
  management change.
- Ridge penalties control the high predictor-to-year ratio.
- Optional second-difference penalties shrink adjacent monthly coefficients
  toward smooth distributed-lag curves.
- Robust Student-t-style iteratively reweighted least squares reduces the
  influence of extreme residuals.
- A pooled, bounded AR(1) estimate can correct a forecast with the latest
  available province residual. Only residuals from earlier years are used.

All numerical estimation is performed through penalized normal equations with
Cholesky decomposition and guarded diagonal jitter. No external R package is
required.

## Trend

Fits `y_it = a_i + b_i t + error_it` independently by province. It is the
minimum weather-free benchmark and should always be retained in comparisons.

## Panel ridge

The `persistence` baseline predicts each region's most recent observed yield,
using only observations preceding the prediction year.

Fits a common 84-term weather response together with regularized province
intercepts and province trends. This is relatively low variance but assumes
all provinces share the same weather sensitivities.

## Local ridge

Fits a separate time trend and 84 weather slopes in each province, with strong
ridge regularization. It permits maximum spatial heterogeneity but learns each
model from a short time series.

## Principal-component regression

The monthly weather matrix is decomposed inside the current training window.
The leading components, global trend, and regularized province effects predict
yield. Component count is tuned chronologically. This is a collinearity-aware
benchmark, not a supervised dimension-reduction method.

## Hierarchical distributed lag

The primary model is

```text
y_it = a + b*t + x_it*beta
       + a_i + b_i*t + x_it*delta_i
       + AR(1) correction + error_it
```

`beta` is the national weather response and `delta_i` is a province deviation
shrunk strongly toward zero. Global and province components are estimated by
penalized backfitting. Separate global and province ridge strengths allow
partial pooling: more flexible than panel ridge and lower variance than fully
local slopes.

## Regularized ensemble

The ensemble combines base predictions with non-negative weights constrained
to sum to one. A penalty shrinks weights toward equal weighting. Its penalty is
chosen by leaving one complete tuning year out at a time; final weights are
then estimated from all tuning forecasts. This grouped procedure acknowledges
that the 16 province errors within a year are not independent.

## Prediction intervals

Province interval half-width is the 80th percentile of absolute rolling-origin
errors in the tuning period. National intervals are calibrated independently
from area-weighted national tuning errors; simply averaging provincial bounds
would ignore spatial error correlation. These are empirical predictive bands,
not parameter-confidence intervals.

