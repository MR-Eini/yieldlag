# YieldLag comparative evaluation protocol

Recorded 2 October 2026 before computing the new German evaluation scores.
This is a prospective computational protocol, not a registered clinical or field study.
The Polish benchmark has already informed development. Prior team exposure to the
German archive is unconfirmed; call it an external dataset, not an untouched
confirmatory test. The frozen v0.2.0 source hashes are in `frozen_v020.json`.

## Questions and primary design

1. Does an asymmetric seasonal anomaly basis improve prediction beyond shared
   linear slopes and regional partial pooling, and under which crops/settings?
2. What changes when tail terms, hot-dry interactions, seasonal smoothing,
   regional deviations, residual AR correction, or robust fitting are removed?
3. How do separated calibration and tuning-error calibration differ in coverage,
   width, and interval score on the same evaluation observations?
4. What predictive skill remains when complete regions are excluded from both
   tuning and fitting?

All primary comparisons use monthly maximum temperature and precipitation (24
terms) so variable definitions can be aligned between the two archives. Poland
targets: wheat, barley; seasons end July and June. Germany: winter wheat and winter
barley; seasons end July and June. Polish aggregate crops and German winter crops
are not identical definitions. Analyze cases separately; do not assert a pooled
country-transfer experiment or physiological thresholds.

Primary chronological periods: initial 1999–2004, tuning 2005–2008,
calibration 2009–2011, evaluation 2012–2018. Exclude 2019 from all primary
selection and fitting; score it separately after models/settings are fixed.
Each origin uses earlier responses/weather for fitting and transforms. Models
may assimilate earlier evaluation responses when progressing through later
origins, as in a sequential retrospective hindcast. Complete harvest-year
weather is assumed; no early-season forecasting claim is made.

Use all regions with at least five initial-period finite responses and matching
weather. Retain later missing response patterns; align methods on the identical
finite test rows. Primary fits are Gaussian (robust FALSE); robustness is an
explicit Polish sensitivity experiment. Regional area weights remain study
weights, so primary inference is on region-year predictions. The 2019 results
and any German national aggregates are supplementary.

## Comparators and controlled ablations

Include trend, persistence, panel ridge, local ridge, PCR, hierarchical partial
pooling, stress-lag, an mgcv GAM with six smooths of temperature/precipitation
over three consecutive four-month seasonal windows, and a ranger random forest.
The GAM and forest are external Gaussian comparators, with no residual AR term.
Package comparisons also report AR-off predictions for the chosen parameters.
The no-AR variant is conditional on the original tuning choice, not retuned.
Also report a simplex ensemble with shrinkage {0,1,10,100,1000,10000}, selected
using leave-one-tuning-year-out stacking. Base hyperparameters were selected on
the same tuning block; this meta-validation is not fully nested. The separate
calibration and later evaluation blocks remain excluded from all selection.

Use lambda {10,100,1000,10000} and smoothing {0,10,100} for panel/local ridge and
stress-lag: 12 candidates each, stress threshold fixed at 0.75. Hierarchical:
global lambda {10,100,1000}, regional/global ratio {3,30}, smoothing {0,10}:
12 candidates. PCR uses {3,5,10,15,20} available components. GAM gamma
{1,1.4,2}; forest mtry {4,8,16}, minimum node size {5,15,30}, 500 trees,
seed 2718, one thread. Record actual fit counts and runtime; unequal candidate
counts mean this is a common temporal protocol, not equal computational cost.
Computational amendment before inspecting German evaluation outcomes: use
mgcv::bam with discrete fREML and two threads for the German GAM, retaining the
same formula, basis size, gamma grid and temporal splits. Standard gam REML is
used for Poland. The first German gam attempts were stopped for runtime; cached
completed non-GAM models were retained. Report this solver distinction.

Stress ablations: linear anomalies; + upper/lower tails; + compound hot-dry;
compound basis without smoothing; compound basis without regional deviations.
Tune each ablation separately on the same tuning years. Threshold {0.5,1,1.5},
Gaussian versus robust fitting, full Polish seven-variable inputs, and shorter
six-month seasons are sensitivities, never selected using evaluation scores.

For spatial testing, group Poland provinces into four deterministic sorted-ID
folds. Entire held regions are removed from tuning and every training origin.
Only methods with supported unseen-region prediction are evaluated. Explicitly
report that zero local yield history differs from prediction in known regions.

## Inference and uncertainty

Report RMSE, MAE, bias, predictive R2, trend-relative squared-error skill,
within-region-centered descriptive R2, annual errors, and paired RMSE differences.
Use 2000 paired circular year-block bootstrap replicates, block length two,
seed 2718, 95% percentile intervals; sensitivity block lengths one and three.
Do not resample province-year rows independently. Seven annual blocks limit
inference and cannot establish universal superiority.

Calibrate nominal 80% intervals from absolute errors in 2009–2011, using the
package's type-8 empirical quantile. This is separate calibration under temporal
dependence, not a distribution-free coverage guarantee. Report coverage, width,
interval score, and the number of calibration years. Compare against intervals
calibrated from tuning errors without changing prediction means.

Native ABSOLUT v1.2 requires a longer history (default minimum 17 years), MPI,
and exhaustive feature searches. An adapter must preserve its GPL code, truncate
input at every forecast origin, and disclose platform changes. Its 2016–2018
comparison is supplementary because it cannot enter the primary early-origin
protocol with its documented minimum history. Do not label a simplified
feature-selection approximation as native ABSOLUT.

## Reporting and unresolved evidence

Publish every completed comparator and sensitivity, including losses and failed
fits. Keep signed permissions, unidentified solar derivation/units and area
averaging period as unresolved provenance fields until evidence arrives. Obtain
an external user's reproduction and human review of AI-assisted code/manuscript.
More than six months of public development cannot be supplied retrospectively.

Sources: Conradt (2022), https://doi.org/10.1007/s00484-022-02356-5;
German archive https://doi.org/10.5281/zenodo.4468691 (CC-BY-4.0 metadata;
agricultural tables additionally attributed under dl-de/by-2-0);
ABSOLUT code https://doi.org/10.5281/zenodo.5789350 (GPL-3.0-or-later).
