# Data attribution and terms

The MIT code license does not relicense provider data. Mohammad Reza Eini
authorized inclusion of these study tables in the public release on 2026-10-02.
Upstream terms remain applicable.

## Weather

Piniewski, M., Szcześniak, M., Kardel, I., and Berezowski, T. (2020),
*G2DC-PL+: A gridded 2 km daily climate dataset for the union of Polish territory
and the Vistula and Odra basins*, Version 1, 4TU.ResearchData.
https://doi.org/10.4121/uuid:a3bed3b8-e22a-4b68-8d75-7b87109c9feb

The catalogue and registered DataCite metadata identify **CC0 1.0 Universal**:
https://creativecommons.org/publicdomain/zero/1.0/. Checked 2026-10-02.
Associated description: https://doi.org/10.5194/essd-13-1273-2021.

These are study-specific monthly province tables, not the original grid.
Eini et al. document aggregation to voivodeships and report climate-source access
on 18 May 2026. The catalogue lists five variables, including wind but not solar
radiation. Local tables add DIF, TAS, and SLR. Their complete derivation and the
SLR unit are not preserved here; the upstream CC0 statement alone does not
establish those derivations. They are included as maintainer-supplied study inputs,
without claiming independently verified solar-radiation provenance.

Unused SPI/SPEI/SMI columns were removed for this release. Selected weather
values were retained verbatim; weather_preparation.csv records source/release
hashes. Original grids and provider logos are not redistributed. The derivatives
are not endorsed by the providers.

## Agricultural statistics

Source: **Statistics Poland (GUS / Central Statistical Office of Poland)**.
The study identifies 1999--2019 yield/cultivation-area statistics obtained via
https://stat.gov.pl/en/national-census/, last access **5 November 2024**.
Supplied project tables were packaged for release **2 October 2026**.

Provider reuse conditions:
https://bip.stat.gov.pl/en/contact-with-the-office/reuse-of-public-sector-information/

The provider requires source, creation/acquisition-time information, and a
processing description, and is not responsible for processed results.
Original publication/table identifiers and issue dates are not preserved here.
The access date is reported by the study, not a separately recovered acquisition
record for each crop column.

Processing: annual region/crop statistics were arranged in CSVs using package
column names. crop_areas.csv contains fixed study weights rather than annual
observations; the averaging recipe is unavailable. CSV numeric values were copied
unchanged. Software then builds seasonal matrices and weighted aggregates.
These derivatives must not be presented as unmodified official GUS products.

## Related study

Eini, M. R., Conradt, T., and Piniewski, M. (2026), *Sequential hybridization
enhances the reliability of a statistical crop yield model - exemplified by
wheat and sugar beet yields in the provinces of Poland*, Theoretical and Applied
Climatology, https://doi.org/10.1007/s00704-026-06322-8.

Recover the documented provenance gaps before claiming complete reconstruction
from original grids or physically interpretable coefficient sensitivities.
