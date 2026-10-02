# cropyieldmodel

[![R package check](https://github.com/MR-Eini/cropyieldmodel/actions/workflows/r-tests.yml/badge.svg)](https://github.com/MR-Eini/cropyieldmodel/actions/workflows/r-tests.yml)
[![Release](https://img.shields.io/github/v/release/MR-Eini/cropyieldmodel)](https://github.com/MR-Eini/cropyieldmodel/releases)

An R package for transparent regional statistical crop-yield modelling.
Prepare weather/yield panels, compare methods chronologically, select a method
using tuning data, and export decisions and predictions for audit.
Maintainer: **Mohammad Reza Eini**.

This initial research-software release requires **R 4.2 or newer** and has no
runtime dependencies outside R's standard libraries. It is not on CRAN.

## Install

```r
install.packages("remotes")
remotes::install_github("MR-Eini/cropyieldmodel", ref = "v0.1.0",
                        build_vignettes = FALSE)
```

Alternatively, download `cropyieldmodel_0.1.0.tar.gz` from the
[release page](https://github.com/MR-Eini/cropyieldmodel/releases/tag/v0.1.0):

```r
install.packages("cropyieldmodel_0.1.0.tar.gz", repos = NULL, type = "source")
```

## Quick example

This small deterministic example uses fictional data and runs without files.
Its accuracy demonstrates API behaviour, not performance on real crops.

```r
library(cropyieldmodel)
data <- synthetic_crop_example()
comparison <- compare_crop_models(
  data,
  config = crop_model_config(
    methods = c("trend", "persistence", "panel_ridge", "ensemble"),
    weather_variables = "TMP",
    grids = list(
      panel_ridge = list(lambda = c(10, 100), smooth_ratio = 0),
      ensemble = list(shrinkage = c(0, 10))
    )
  ),
  last_yield_year = 2015, predict_through = 2016, verbose = FALSE
)
summary(comparison)
model <- get_crop_model(comparison)
predict(model, data$panel[data$panel$Year == 2016, ], interval = "prediction")
write_crop_results(comparison, "results/synthetic")
```

For your own panel, use `prepare_crop_data()` with explicit column mappings.
Read the tutorials under `vignettes/`, or install with `build_vignettes = TRUE`
and use `vignette("getting-started", package = "cropyieldmodel")`.

## Methods and outputs

- Province trend and last-observation persistence baselines.
- Panel ridge, local ridge, principal-component regression, and a hierarchical
  distributed-lag model with optional robust fitting and pooled AR(1) correction.
- An ensemble with non-negative weights summing to one.
- Rolling-origin tuning followed by later rolling evaluation.
- Automatic method selection using province-year **tuning RMSE only**.
- Empirical 80% intervals calibrated in tuning, with separate national calibration.
- Area-weighted aggregation, candidate grids, row-level predictions, metrics,
  model objects, configuration, checksums, figures, and session information.

## Poland example and reproduction

The bundled case study contains annual yields and fixed area weights for 16
Polish voivodeships and monthly weather. The reader rebuilds 84 monthly terms
from seven variables and twelve months, without previous fitted results.

```r
wheat <- read_crop_data(poland_example_path(), "wheat", harvest_month = 7)
comparison <- compare_crop_models(wheat, last_yield_year = 2018,
                                  predict_through = 2019)
write_crop_results(comparison, "results/wheat")
```

The full grid is substantially slower than the quick example. From a checkout,
`./reproduce.ps1` builds and installs the current source in an isolated library
and runs the full barley comparison. On other platforms, install the package,
then run `Rscript analysis/reproduce_poland.R`.

With observations through 2018, the default split is initial history 1999--2005,
tuning 2006--2011, evaluation 2012--2018, final fitting 1999--2018, and a
retrospective 2019 forecast using 2019 weather. Rolling forecasts use yield
data strictly before the forecast year. Preprocessing is fitted within each
training window. See [validation](docs/VALIDATION.md).

## Data terms and scientific limits

Code is MIT licensed: [LICENSE.md](LICENSE.md). Data have separate terms:
[data attribution](inst/extdata/poland/DATA_LICENSE.md) and [data contract](docs/DATA.md).
G2DC-PL+ is CC0; Statistics Poland data require source and processing attribution.
Bundled tables are study-specific derivatives, not official new source editions.
Solar-radiation units and derivation are not established by the local tables;
confirm them before interpreting coefficients as physical sensitivities.

This is a statistical framework, not a simulator of physiology, management,
soil water balance, pests, or phenology. Complete harvest-year weather makes
these forecasts retrospective. Fixed study area weights also make national
results a retrospective benchmark, rather than prospective national forecasting.

The evaluation period has already been inspected during development and is
not an untouched confirmatory test. Province-year errors are correlated, and
national evaluation contains only seven years. External periods/countries,
spatial holdouts, and uncertainty for metric differences remain necessary.
No estimator wins for every crop; empirical interval labels are not externally
validated coverage guarantees.

## Citation and development

Use `citation("cropyieldmodel")` or GitHub's **Cite this repository** button.
The related study is Eini, Conradt, and Piniewski (2026), *Theoretical and Applied
Climatology*, [doi:10.1007/s00704-026-06322-8](https://doi.org/10.1007/s00704-026-06322-8).
The software supplies a separate estimator and workflow; the study's results
are not validation of these new estimators.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [publication strategy](docs/PUBLICATION_STRATEGY.md).
The public repository contains source, examples, and tests. Legacy models and
generated research outputs remain in the original local project.
