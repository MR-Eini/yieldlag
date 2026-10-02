# Reproduce the comparative evaluation

Run commands from the repository root using R 4.2 or later and Python 3.10 or
later. Read `protocol.md` before interpreting the outputs. The published CSVs
and plots can be inspected without rerunning models.

Install R dependencies:

```r
install.packages(c("mgcv", "ranger", "foreach", "leaps", "jsonlite"))
install.packages("yieldlag_0.3.0.tar.gz", repos = NULL, type = "source")
```

Download the checksum-verified German archive:

```sh
python research/download_external.py
```

For each case `poland_wheat`, `poland_barley`, `germany_wheat`, `germany_barley`:

```sh
Rscript research/run_study.R poland_wheat
Rscript research/augment_study.R poland_wheat
```

Scripts cache completed fitted models locally. For an independent rerun, use a
fresh checkout so no cached objects can replace new fitting. German GAMs and
the full sensitivities can take substantial time; scripts report progress.

Run the Polish spatial and feature sensitivities for each crop (`wheat`, `barley`):

```sh
Rscript research/run_spatial.R wheat
Rscript research/run_sensitivity.R wheat
```

Run the separately downloaded GPL ABSOLUT software for each Polish case, then
repeat augmentation to join native predictions and matched-period scores:

```sh
python research/run_absolut.py poland_wheat
Rscript research/augment_study.R poland_wheat
```

The upstream adapter preserves native settings and writes its own manifests.
Its downloaded source license remains GPL; it is not part of the MIT package.

To rebuild the scientific figures, manuscript and research page:

```sh
python -m pip install numpy pandas matplotlib reportlab markdown
python research/build_evidence.py
python analysis/verify_research.py
python analysis/verify_website.py
```

The website build also requires the existing v0.2.0 Poland reference exports;
the new research study does not replace their recorded configuration. Exported
row-level predictions, candidate scores, selected settings, runtime and session
information accompany each case. `independent_reproduction.md` specifies the
separate human replication exercise, which has not yet been completed.
