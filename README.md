# YieldLag

[![R package check](https://github.com/MR-Eini/yieldlag/actions/workflows/r-tests.yml/badge.svg)](https://github.com/MR-Eini/yieldlag/actions/workflows/r-tests.yml)
[![Release](https://img.shields.io/github/v/release/MR-Eini/yieldlag)](https://github.com/MR-Eini/yieldlag/releases)

**Regional crop-yield modelling from seasonal climate.**

YieldLag fits interpretable statistical models to regional yield and monthly
weather panels. It combines smooth seasonal responses, regional effects,
nonlinear weather anomalies, and chronological model comparison.

## Installation

Requires R 4.2 or later. Model estimation uses R's standard libraries.

```r
install.packages("remotes")
remotes::install_github("MR-Eini/yieldlag", ref = "v0.2.0",
                        build_vignettes = FALSE)
```

A source package with rendered tutorials is available from
[GitHub Releases](https://github.com/MR-Eini/yieldlag/releases).

## Seasonal stress responses

The `stress_lag` estimator adds asymmetric anomaly responses and compound
hot-dry terms to a regularized regional model:

- Each training window estimates region-specific monthly means and pooled
  within-region variability.
- Separate upper and lower anomaly terms allow different responses to unusually
  high and low weather values.
- Explicit temperature and precipitation mappings enable same-month hot-dry
  interactions.
- Ridge and second-difference penalties regularize effect magnitudes and
  variation across seasonal months.

Thresholds are standardized weather anomalies, not physiological crop-damage
thresholds. [Model specification](docs/MODELS.md) defines the basis and penalties.

## Example

The deterministic example below contains a declared nonlinear response and
fictional weather. It illustrates the estimator and does not measure real-crop skill.

```r
library(yieldlag)
data <- synthetic_stress_example()

config <- crop_model_config(
  methods = c("trend", "panel_ridge", "stress_lag", "ensemble"),
  weather_variables = c("TMP", "PCP"),
  stress_temperature = "TMP",
  stress_precipitation = "PCP",
  robust = FALSE,
  grids = list(
    panel_ridge = list(lambda = c(1, 10), smooth_ratio = 0),
    stress_lag = list(lambda = c(1, 10), smooth_ratio = 0,
                      threshold = c(0.5, 1)),
    ensemble = list(shrinkage = c(0, 10))
  )
)
comparison <- compare_crop_models(data, config, 2030, 2031, verbose = FALSE)
summary(comparison)

model <- get_crop_model(comparison, "stress_lag")
future <- subset(data$panel, Year == 2031)
predict(model, future, interval = "prediction")
explain_crop_prediction(model, future)
prediction_support(model, future)
write_crop_results(comparison, "results/stress_example")
```

`explain_crop_prediction()` decomposes a stress-lag prediction into trend,
regional, weather, compound, and residual components that sum to its prediction.
Components are statistical contributions relative to training feature means.
`prediction_support()` flags terms outside observed training ranges and unseen
regions; it is a diagnostic rather than a calibrated measure of forecast confidence.

## Estimators

| Method | Response structure |
|---|---|
| `trend` | Independent regional yield trends |
| `persistence` | Most recent regional observed yield |
| `panel_ridge` | Shared weather response with regional intercepts and trends |
| `local_ridge` | Separate regularized regional weather responses |
| `pcr` | Training-window principal components and regional effects |
| `hierarchical` | Partially pooled seasonal weather responses |
| `stress_lag` | Asymmetric seasonal anomalies and optional hot-dry interactions |
| `ensemble` | Non-negative, sum-to-one combination of base estimators |

## Data and validation

Use `prepare_crop_data()` for in-memory panels with explicit column mappings.
For the bundled Poland example:

```r
wheat <- read_crop_data(poland_example_path(), "wheat", harvest_month = 7)
```

Examples retain all declared monthly terms. Rolling fits use observations
preceding each forecast year. Hyperparameters, ensemble settings, method
selection, and empirical 80% interval calibration use the tuning period;
a later period evaluates the selected procedure. The result bundle includes
candidate scores, row-level predictions, model objects, decompositions,
support diagnostics, and input/output checksums.

The Poland example uses complete harvest-year weather and fixed area weights;
it is a retrospective benchmark. National observations are constructed from
weighted provincial yields. Monthly data cannot resolve daily heat exposure.
Neither prediction decompositions nor model coefficients establish causal effects.
[Validation](docs/VALIDATION.md) and [data documentation](docs/DATA.md) describe
these assumptions and interpretation limits.

## Citation and license

Maintainer: **Mohammad Reza Eini**. Use `citation("yieldlag")` to cite the software.

The Poland data setting is described by Eini, Conradt, and Piniewski (2026),
[Theoretical and Applied Climatology](https://doi.org/10.1007/s00704-026-06322-8).
Nonlinear exposure responses and distributed-lag models have an established
literature; YieldLag implements a regularized seasonal basis for regional yield panels.

Code: [MIT](LICENSE.md). Bundled data:
[source attribution and terms](inst/extdata/poland/DATA_LICENSE.md).
