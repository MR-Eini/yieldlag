# Poland example data

Annual yields, fixed crop-area weights, monthly weather, and crop-season
metadata for 16 voivodeships. Use
`read_crop_data(poland_example_path(), "wheat", harvest_month = 7)`.

`DATA_LICENSE.md` documents sources and terms. `input_sha256.csv` lists numeric
input hashes. Preparation manifests record column/row filtering and source hashes.
National reference yields are constructed from weighted provincial observations.
Weather-variable and area-weight metadata are described in `docs/DATA.md`.
