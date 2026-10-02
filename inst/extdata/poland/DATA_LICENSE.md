# Data sources and terms

## Climate

Piniewski, M., Szcześniak, M., Kardel, I., and Berezowski, T. (2020),
*G2DC-PL+: A gridded 2 km daily climate dataset for the union of Polish territory
and the Vistula and Odra basins*, Version 1, 4TU.ResearchData.
https://doi.org/10.4121/uuid:a3bed3b8-e22a-4b68-8d75-7b87109c9feb.

The source catalogue identifies CC0 1.0 Universal:
https://creativecommons.org/publicdomain/zero/1.0/.
Dataset description: https://doi.org/10.5194/essd-13-1273-2021.

The example contains monthly voivodeship tables derived for the associated study.
The source catalogue lists precipitation, minimum/maximum temperature, humidity,
and wind. The example also contains temperature difference, mean temperature,
and solar radiation. Full aggregation lineage, solar-radiation derivation/unit,
and the relationship of these additional columns to the catalogue variables
are unspecified. Source CC0 metadata alone do not establish that lineage.

The selected weather values are unchanged; unused drought-index columns were
excluded. `weather_preparation.csv` records source and distributed SHA-256 hashes.
The tables are study derivatives and carry no provider endorsement.

## Agricultural statistics

Source: Statistics Poland (GUS / Central Statistical Office of Poland).
The associated study identifies 1999--2019 yield and cultivation-area statistics
obtained via https://stat.gov.pl/en/national-census/, last accessed 5 November 2024.

Reuse terms:
https://bip.stat.gov.pl/en/contact-with-the-office/reuse-of-public-sector-information/.
The provider requires attribution, creation/acquisition-time information, and
a processing description, and is not responsible for processed results.
Original table identifiers, issue dates, and crop-specific acquisition records
are unspecified; the access date above is reported by the associated study.

Processing: provincial values are arranged in crop/year CSV tables with standardized
column labels. Areas are fixed study weights; their averaging period is unspecified.
Derived unweighted national-mean rows are excluded. National reference yields
are computed from provincial observations using the declared area weights.
`yield_preparation.csv` records filtering and source/distributed hashes.
These derivatives should not be represented as unmodified official GUS products.

## Study

Eini, M. R., Conradt, T., and Piniewski, M. (2026), *Sequential hybridization
enhances the reliability of a statistical crop yield model - exemplified by
wheat and sugar beet yields in the provinces of Poland*, Theoretical and Applied
Climatology, https://doi.org/10.1007/s00704-026-06322-8.

## Software license

The MIT license applies to software, not to the provider data. Data users
must retain the attribution and processing information above.
