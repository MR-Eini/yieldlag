# Contributing

Report bugs and propose changes at https://github.com/MR-Eini/yieldlag/issues.
Include a minimal example, expected and observed behaviour, package version,
and `sessionInfo()`. Use synthetic data when research data cannot be shared.

For development, install `testthat`, `roxygen2`, `knitr`, and `rmarkdown`.
Run `roxygen2::roxygenise()`, `testthat::test_local()`, and `R CMD build .`
followed by `R CMD check --no-manual yieldlag_<version>.tar.gz`.
The GitHub workflow checks Windows, macOS, current R on Linux, and R 4.2.

Add an independent regression test for a bug fix. Preserve the chronological
training contract: changing later yields or weather must not change earlier
rolling forecasts or tuning decisions. Document any change in model defaults,
data transformations, validation design, and exported artifacts in `NEWS.md`.
Do not commit fitted models, run outputs, credentials, or machine paths.

Pull requests contribute code under the MIT license. Data retain their own
provider terms; see `inst/extdata/poland/DATA_LICENSE.md`.
