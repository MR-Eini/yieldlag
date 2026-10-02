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
