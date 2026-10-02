# Data specification

## Panel interface

`prepare_crop_data()` requires one row per region/year, finite declared weather
terms, and yield observations or NA for forecast years. Column mappings are
explicit. Optional areas must be positive, finite, and unique by region;
national observations must have unique years.

The manifest maps terms to variable labels, calendar months, and seasonal
positions. Compound terms require explicit temperature/precipitation mappings
with matching months and positions. Variable names imply no physiological thresholds.

## Directory interface

`read_crop_data()` reads yield.csv, crop_areas.csv, and weather/pl_<region>.dat.
RS identifiers above 999 represent provinces in this schema. Use the in-memory
interface for other layouts. `poland_example_path()` locates installed example inputs.

## Poland example

| Input | Scope |
|---|---|
| Yield | Provincial crop/aggregate/forage targets, 1999--2019; dt/ha |
| Area | Fixed crop-specific study weights; hectares |
| Weather | Monthly provincial values, 1990--2019 |
| Seasons | Target-specific agricultural-year endpoint assumptions |

Crop yields use dt/ha (100 kg/ha). Area-weight averaging periods and detailed
spatial/monthly weather aggregation lineage are unspecified. Weather working
conventions are Celsius for MAX/MIN/TAS/DIF, percent for HMD, and monthly mm
for PCP; these conventions have not been independently verified against source
grids. SLR denotes solar radiation with an unspecified numeric unit/derivation.
No automatic unit conversions are applied.

An agricultural year ending in June uses July--December of the previous year
and January--June of the harvest year. Seven variables produce 84 monthly terms.
The manifest records the term/calendar mapping. Incomplete initial seasonal
windows are omitted; requested cutoffs are validated by the workflow.

National references are weighted provincial observations, not independent national
measurements. Fixed areas and full harvest-year weather define a retrospective
benchmark. Earlier forecasts require inputs available at the intended issue date.

`input_sha256.csv` records input bytes. Preparation manifests document exclusion
of unused drought indices and derived unweighted national-mean rows; retained
provincial and selected weather values are unchanged.
[Data attribution](../inst/extdata/poland/DATA_LICENSE.md) describes source terms.
