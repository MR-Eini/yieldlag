# Independent YieldLag reproduction

An independent researcher should complete this protocol in a clean environment
and return their own logs and observations. Author-run checks are not evidence
that this independent exercise has occurred.

1. Download the tagged source release, record its SHA-256, install it in a fresh
   R library, and record operating system, R version and `sessionInfo()`.
2. Run the included synthetic example and one Polish example without author
   assistance. Compare exported predictions and metrics with the published CSVs.
3. Prepare an independently owned dataset with one region/year row and the
   declared monthly-weather manifest. Record crop definitions, yield units,
   monthly weather units, season, spatial support, missingness and permission.
4. Choose initial/tuning/calibration/evaluation periods before examining later
   scores. Run at least trend, panel ridge, hierarchical and stress-lag. Use
   `calibration_years` to separate calibration from model selection.
5. Check that changing later yields does not change tuning choices; inspect
   interval coverage, year-specific errors, extrapolation flags and limitations.
6. Record installation time, runtime, unclear documentation, any code changes,
   scientific interpretation issues, and failures. Report the unsuccessful cases
   as well as successful ones. Do not infer causal damage from decomposition.
7. Return the inputs' provenance, permitted data or a reproducible access route,
   configuration, raw logs, CSV outputs, checksums and a signed/date-stamped
   statement describing what was run independently and what assistance occurred.

Contact: Mohammad Reza Eini, mohammad_eini@sggw.edu.pl.
No invitation has been sent and no external reproduction is claimed.
