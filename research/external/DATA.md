# External benchmark attribution

The German input archive is pinned to Tobias Conradt's 2021 record,
[DOI 10.5281/zenodo.4468691](https://doi.org/10.5281/zenodo.4468691).
Archive metadata specifies CC BY 4.0. Agricultural tables additionally identify
the statistical offices of the German federation and states, copyright 2020,
and the Data licence Germany attribution 2.0. Retain those source notices when
using or redistributing inputs or derivatives; the software MIT license does
not replace data terms.

Weather inputs derive from DWD rasters, with BKG district boundaries and
Copernicus CORINE Land Cover 2012 in the archived processing description.
`download_manifest.json` records source URLs, upstream MD5 checksums and verified
SHA-256 hashes. The primary study maps `tasmax` to `MAX` and `pr` to `PCP` and
uses harvest-year seasons and yield units of dt/ha. Crop definitions, spatial
scale and missingness differ from the Polish provincial examples.

The separate ABSOLUT v1.2 software archive is
[DOI 10.5281/zenodo.5789350](https://doi.org/10.5281/zenodo.5789350),
by Tobias Conradt, Potsdam Institute for Climate Impact Research. Its source
headers specify GPL version 3 or later. `run_absolut.py` downloads that source
into a separate directory and records portability modifications and hashes.
The MIT package contains no copied upstream implementation. Cite Conradt (2022),
[doi:10.1007/s00484-022-02356-5](https://doi.org/10.1007/s00484-022-02356-5),
for the original method and archive processing.
