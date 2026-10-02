# YieldLag 0.3.0

- Added a separate chronological calibration block through `calibration_years`.
- Added `compare_crop_errors()` for paired year-block uncertainty intervals.
- Added controlled stress-basis and regional-effect ablations.
- Added reproducible Poland/Germany comparisons, external GAM/forest baselines,
  spatial holdouts, upstream ABSOLUT comparisons, and calibration diagnostics.
- Retained version 0.2.0 predictions and the original Poland explorer as a
  separately specified reference experiment.
- Handled constant-response correlations without emitting numerical warnings.

# YieldLag 0.2.0

- Added `stress_lag`: regional seasonal climatology, asymmetric anomaly terms,
  optional hot-dry interactions, and regularized monthly response curves.
- Added `explain_crop_prediction()` for exact additive stress-lag decomposition.
- Added `prediction_support()` for training-range and unseen-region diagnostics.
- Added a deterministic compound-stress example and independent regression tests.
- Exported nonlinear basis coefficients, prediction components, and support diagnostics.
- Renamed the R package and repository to `yieldlag`.
- Revised documentation around model specification, usage, and validation.

# 0.1.0

- Introduced regional statistical estimators, chronological comparison, ensembles,
  tuning-only method selection, empirical intervals, and reproducible result exports.
- Included Poland provincial yield/weather inputs with data-source attribution.
- Validated metric-vector lengths, temporal splits, and national-yield identifiers.
