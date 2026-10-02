# Package assessment and publication strategy

## Assessment

The project already had an installable base-R package, public S3 interfaces,
six estimators plus an ensemble, chronological tuning/evaluation, result exports,
function documentation, and vignettes. Its earlier local check had no errors or
warnings, but maintainer metadata were placeholders.

The initial public release adds maintainer metadata, repository/issue URLs,
MIT text, GitHub and R citations, a small synthetic example, data attribution
and preparation hashes, contribution instructions, four platform/R checks, and
independent temporal-contract tests. It also rejects impossible temporal splits,
unequal metric vectors, and duplicate national-yield years.
The supplied national yield rows proved to be unweighted provincial means
(294 of 294 values). They were removed so the example's national score uses
area-weighted provincial observations, with no claim of independent national data.

## Recommended sequence

1. **GitHub v0.1.0 research-software release.** Publish clean package source,
   the Poland example, documentation, source tarball, and SHA-256. Preserve
   legacy scripts and historical outputs locally. Describe it as usable software
   without asserting universal predictive superiority.
2. **Archive a software DOI.** Connect GitHub to Zenodo, archive a release, then
   add the actual version DOI to citations. No DOI is invented or borrowed from
   the related paper. Archival-service setup is a separate step.
3. **Improve documentation and provenance.** Add pkgdown documentation; recover
   exact spatial/monthly aggregation and solar-radiation derivation/units; archive
   annual area observations and their availability dates.
4. **Validate before a methods paper.** Use untouched later data, spatial
   holdouts, year/block bootstrap uncertainty, season/grid sensitivity,
   operationally available weather, and annual weights available at each origin.
   Report weak crops as well as gains, comparing persistence, trend, and relevant
   published methods using the same information.
5. **CRAN after stabilization.** Resolve provenance gaps, check minimum/current/
   development R, keep examples quick, review incoming notes and URLs, and freeze
   the API. CRAN distribution does not independently validate scientific claims.

## Scientific priorities

- Seven national evaluation years and correlated provincial rows require uncertainty.
- The inspected development period cannot serve as untouched confirmatory evidence.
- Fixed study area weights are retrospective rather than prospective yearly weights.
- Harvest-year weather requires explicit issue dates for early warning applications.
- Predictor units/processing and crop seasons need domain review.
- Unseen-region prediction is unsupported for methods with local components;
  pooled methods still need external validation.
- Empirical 80% tuning-error bands do not guarantee coverage on new populations.

## Scope

No old research simulations are rerun and no historical outputs are overwritten.
Verification uses synthetic tests, raw-data matrix checks, and the installed
package. The related paper documents the setting, not an independent test of
this new estimator family.
