# Poland case-study inputs

Annual yields, fixed crop-specific area weights, monthly weather through 2019,
and season assumptions for 16 voivodeships. Read DATA_LICENSE.md for source
terms and provenance gaps. The code MIT license does not apply to provider data.
Unused drought indices were removed; selected weather values were retained
verbatim. weather_preparation.csv records preparation; input_sha256.csv records
numeric inputs. Use `read_crop_data(poland_example_path(), "wheat", 7)`.

The package reproduces from supplied monthly tables. A full reconstruction
from original gridded data remains a documentation task.
