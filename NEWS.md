# cropyieldmodel 0.1.0

- Published an initial GitHub research-software release with software and data
  attribution, R/GitHub citations, and checks across four R/platform configurations.
- Added a public deterministic synthetic example independent of Poland data.
- Added a regression test that perturbs later responses and weather to verify
  earlier predictions and tuning decisions remain unchanged.
- Rejected impossible temporal splits, unequal metric vector lengths, and
  duplicated national-yield years before they can silently affect results.
- Removed unused drought-index columns from the public weather tables and
  recorded original and release SHA-256 hashes.
- Added an installable, base-R crop-yield modelling package.
- Added explicit constructors for directory-based and arbitrary panel data.
- Added direct fitting and prediction interfaces for six base methods,
  including a last-observation persistence benchmark.
- Added chronological tuning, later evaluation, and regularized ensembles.
- Added tuning-only automatic method selection to prevent post-hoc selection
  from the evaluation period.
- Added complete reproducibility bundles with row-level predictions,
  configuration, checksums, model objects, reports, figures, and session data.
- Added independent synthetic unit tests and bundled Poland case-study inputs.
