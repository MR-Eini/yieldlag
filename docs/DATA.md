# Data contract

`prepare_crop_data()` accepts a unique region/year panel, finite declared weather
terms, optional positive area weights, and optional national observations with
unique years. Missing yields are permitted for forecast years. Mappings are explicit.

`read_crop_data()` reads yield.csv, crop_areas.csv, and weather/pl_<region>.dat.
`poland_example_path()` locates the installed example. RS above 999 represents
provinces; the named Poland row supplies national observations. Use the in-memory
constructor for other schemas.

## Bundled inputs and processing

- Yields: 1999--2019, dt/ha (100 kg/ha).
- Area weights: fixed study weights in hectares; not annual prospective weights.
  The exact averaging recipe is not supplied.
- Weather: 1990--2019, supplied monthly province values retained without conversion.
- Seasons: assumptions in inst/extdata/poland/crop_seasons.csv.
- Sources/terms: inst/extdata/poland/DATA_LICENSE.md.
- weather_preparation.csv records original/release SHA-256 and the removal of
  unused SPI/SPEI/SMI columns. Seven weather columns and dates are unchanged.
- input_sha256.csv records every included numeric CSV/DAT input.

The paper defines SLR as solar radiation, PCP as precipitation, MAX/MIN as
maximum/minimum temperature, HMD as humidity, DIF as MAX minus MIN, and TAS as
mean temperature. Working conventions are Celsius for temperatures/differences,
percent for humidity, and monthly mm for precipitation; these are not independently
verified against the original grids. Solar-radiation scale/unit and derivation are
unconfirmed. Preserve supplied scales for reproduction; verify units/aggregation
before transfer or physical interpretation. Upstream G2DC-PL+ lists precipitation,
min/max temperature, humidity, and wind, rather than solar radiation. DIF, TAS,
and SLR are study-specific derived columns whose full recipes need recovery.

## Agricultural year

For harvest year t ending in June, July--December of t-1 precedes January--June
of t. Seven variables contribute twelve months each, giving 84 terms. Wheat
ending in July uses August--December then January--July. Each output bundle
records the complete feature/calendar mapping. Initial/incomplete seasonal
windows are omitted by the reader; the workflow checks requested cutoffs.

Using 2019 weather and training only through 2018 makes the example retrospective.
Observed 2019 yields exist in the file but are withheld from fitting under that cutoff.
