"""Build the static YieldLag documentation site from package help and saved results.

Dependency: Python-Markdown. Run from the repository root after figure export
and R tools::Rd2HTML rendering into outputs/website_reference.
"""
from pathlib import Path
import html
import hashlib
import json
import re
import shutil
import markdown
from plot_poland_website import FIGURES, LABELS

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
DATA = json.loads((SITE / "assets/data/poland.json").read_text(encoding="utf-8"))
ESC = html.escape
LOGO = '<svg viewBox="0 0 28 36" fill="none" aria-hidden="true"><path d="M14 34V5M14 15C4 15 3 8 3 8C11 8 14 11 14 15ZM14 23C24 23 25 16 25 16C17 16 14 19 14 23ZM14 6C9 0 14 0 14 0C20 0 17 5 14 6Z" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>'
NAV = [("Overview", "index.html"), ("Guide", "guide.html"), ("Models", "models.html"),
       ("Poland example", "poland.html"), ("Research", "research.html"), ("Reference", "reference/index.html")]

def shell(title, body, active, prefix="", description="", scripts=()):
    navigation = ''.join(f'<a href="{prefix}{url}"'+(' class="active" aria-current="page"' if label == active else '')+f'>{label}</a>' for label, url in NAV)
    def asset(path):
        version = hashlib.sha256((SITE/path).read_bytes()).hexdigest()[:12]
        return prefix+path+'?v='+version
    script_tags = ''
    for path in scripts:
        data = f' data-results="{asset("assets/data/poland.json")}"' if path == 'assets/poland.js' else ''
        script_tags += f'<script defer src="{asset(path)}"{data}></script>'
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{ESC(title)} · YieldLag</title><meta name="description" content="{ESC(description or 'YieldLag: seasonal climate responses and regional crop yield modelling. Documentation, models and reproducible Poland results.')}">
<meta name="theme-color" content="#21624d"><link rel="icon" href="{prefix}assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{asset("assets/style.css")}"><script defer src="{asset("assets/app.js")}"></script>
{script_tags}</head><body>
<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><div class="wrap header-row"><a class="brand" href="{prefix}index.html">{LOGO}YieldLag<span class="version">0.3.0</span></a>
<button class="nav-button" aria-label="Toggle navigation" aria-expanded="false" aria-controls="main-nav">Menu</button><nav id="main-nav" aria-label="Main navigation">{navigation}<a href="https://github.com/MR-Eini/yieldlag" target="_blank" rel="noopener">GitHub ↗</a></nav></div></header>
<main id="main">{body}</main><footer class="footer"><div class="wrap footer-row"><div>YieldLag 0.3.0 · Mohammad Reza Eini<br>Seasonal climate responses and regional crop yield modelling.</div><div><a href="{prefix}citation.html">Citation & data</a><a href="https://github.com/MR-Eini/yieldlag/releases/tag/v0.3.0">Download</a><a href="https://github.com/MR-Eini/yieldlag/issues">Report an issue</a></div></div></footer></body></html>'''

def write(name, content):
    p = SITE / name
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(content, encoding="utf-8", newline="\n")

def hero(kicker, title, lead):
    return f'<section class="hero wrap"><span class="eyebrow">{kicker}</span><h1>{title}</h1><p class="lead">{lead}</p></section>'

def md(source):
    return markdown.markdown(source, extensions=["tables", "fenced_code", "toc"])

def layout(prose, contents):
    toc = '<aside class="toc" aria-label="On this page">'+''.join(f'<a href="#{anchor}">{label}</a>' for anchor, label in contents)+'</aside>'
    return '<div class="wrap content-layout">'+toc+'<article class="prose">'+prose+'</article></div>'

def metric_table(crop, level="Province-year"):
    rows = [r for r in DATA[crop]["model_metrics"] if r["Level"] == level]
    columns = [("RMSE", "RMSE"), ("MAE", "MAE"), ("Bias", "Bias"), ("R2", "R²"), ("Coverage80", "80% coverage"), ("MeanWidth80", "Band width")]
    body = ''
    for row in rows:
        selected = row["SelectedByTuning"]
        label = LABELS[row["Method"]]+(' <span class="badge">tuning-selected</span>' if selected else '')
        values = ''.join(f'<td class="numeric">{row[key]*100:.1f}%</td>' if key == "Coverage80" else f'<td class="numeric">{row[key]:.3f}</td>' for key, _ in columns)
        body += ('<tr class="selected">' if selected else '<tr>')+f'<td>{label}</td>'+values+'</tr>'
    return '<table><thead><tr><th scope="col">Method</th>'+''.join(f'<th scope="col">{label}</th>' for _, label in columns)+'</tr></thead><tbody>'+body+'</tbody></table>'

def figure(name, title, caption, crop="barley"):
    return f'''<figure class="plot-card" id="figure-{name}"><h3>{title}</h3><a data-plot-link="{name}" href="assets/plots/{crop}/{name}.png"><img loading="lazy" data-plot="{name}" src="assets/plots/{crop}/{name}.png" alt="{ESC(title)} for Poland {crop}; {ESC(caption)}"></a><figcaption>{caption}</figcaption><div class="plot-links"><a data-plot-download="{name}:png" href="assets/plots/{crop}/{name}.png" download>Download PNG</a><a data-plot-download="{name}:svg" href="assets/plots/{crop}/{name}.svg" download>Download SVG</a></div></figure>'''

def build():
    write('assets/favicon.svg', '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 40"><rect width="40" height="40" rx="8" fill="#21624d"/><path d="M20 33V7M20 17C10 17 10 10 10 10C17 10 20 13 20 17ZM20 25C30 25 30 18 30 18C23 18 20 21 20 25Z" fill="none" stroke="#faf9f5" stroke-width="2"/></svg>')
    overview = '''<section class="hero wrap hero-grid"><div><span class="eyebrow">An R package for seasonal climate & crop yields</span><h1>Understand the season.<br>Model the yield.</h1><p class="lead">Interpretable regional models that connect monthly weather to crop yield, compare methods chronologically, and explain their predictions.</p><div class="actions"><a class="button" href="guide.html">Get started with R →</a><a class="button secondary" href="poland.html">Explore the Poland results</a></div><p class="small" style="margin-top:22px">R ≥ 4.2 · Standard-library model estimation · MIT code</p></div><div class="hero-art"><span class="eyebrow" style="margin-bottom:18px">Observed data · reproducible comparison</span><img src="assets/plots/barley/model_comparison.png" alt="Barley evaluation RMSE: hierarchical modelling has the lowest provincial and national RMSE."><p>Eight estimators. The same evaluation years.<br>Every score comes from the bundled Poland example.</p></div></section>
<section class="rule-section"><div class="wrap"><div class="section-head"><h2>From weather panels<br>to interpretable results.</h2><p>A complete statistical workflow: data preparation, model tuning, rolling evaluation, fitting, prediction, and result export.</p></div><div class="grid"><article class="card"><span class="number">01</span><h3>Respect time</h3><p>Preprocessing and coefficients use earlier years at every forecast origin. Tune on an earlier block, then evaluate the procedure on later years.</p></article><article class="card"><span class="number">02</span><h3>Represent seasonal response</h3><p>Compare pooled and regional effects, smooth monthly coefficients, asymmetric weather anomalies, and compound hot–dry interactions.</p></article><article class="card"><span class="number">03</span><h3>Inspect the prediction</h3><p>Break a stress-lag prediction into additive components. Diagnose weather extrapolation, empirical intervals, and regional errors.</p></article></div></div></section>
<section class="rule-section"><div class="wrap split"><div><span class="eyebrow">A compact R interface</span><h2 style="margin-top:15px">Start with a panel.<br>Keep the evidence.</h2><p>Use bundled inputs or provide your own region/year panel. A comparison object retains tuning candidates, selected settings, row-level predictions, model objects, and diagnostics.</p><a href="reference/index.html">Explore the function reference →</a></div><div><pre><code>install.packages("remotes")
remotes::install_github("MR-Eini/yieldlag",
                        ref = "v0.3.0")
library(yieldlag)

data &lt;- read_crop_data(
  poland_example_path(), "barley", 6
)
config &lt;- crop_model_config(
  stress_temperature = "MAX",
  stress_precipitation = "PCP"
)
result &lt;- compare_crop_models(
  data, config, 2018, 2019
)</code></pre></div></div></section>
<section class="rule-section"><div class="wrap"><div class="section-head"><h2>A Poland example<br>you can inspect.</h2><p>Barley and wheat across 16 provinces. Explore predictions, evaluation metrics, seasonal coefficients, regional differences, and the exported tables.</p></div><div class="stats"><div class="stat"><strong>16</strong><span>Polish provinces</span></div><div class="stat"><strong>84</strong><span>Monthly weather terms per crop</span></div><div class="stat"><strong>8</strong><span>Methods compared</span></div><div class="stat"><strong>112</strong><span>Evaluation province-years per crop</span></div></div><div class="note">These are retrospective benchmarks using complete seasonal weather and fixed area weights. They measure statistical associations and predictive performance in this dataset; they do not establish causal crop responses or operational early-forecast skill.</div><div class="actions"><a class="button" href="poland.html">Open the result explorer →</a></div></div></section>'''
    write('index.html', shell('Seasonal climate. Regional yields.', overview, 'Overview'))

    guide = '''## Install {#install}

The model engine uses R's standard libraries. R 4.2 or later is required.

```r
install.packages("remotes")
remotes::install_github("MR-Eini/yieldlag", ref = "v0.3.0",
                        build_vignettes = FALSE)
library(yieldlag)
```

Alternatively, download `yieldlag_0.3.0.tar.gz` from [the release](https://github.com/MR-Eini/yieldlag/releases/tag/v0.3.0) and use `install.packages(path, repos = NULL, type = "source")`. The release archive includes rendered tutorials. The package name is `yieldlag`.

## Prepare data {#data}

The directory interface reads the bundled study layout:

```r
barley <- read_crop_data(poland_example_path(), "barley",
                        harvest_month = 6)
wheat <- read_crop_data(poland_example_path(), "wheat",
                       harvest_month = 7)
```

The harvest month is the endpoint of a 12-month agricultural window, not a physiological phenology model. Barley uses July–June; wheat uses August–July. Seven variables × twelve months produce 84 terms.

For your own data, use `prepare_crop_data()` with one row per region/year, finite weather terms, and yield values or `NA` for prediction years. Map names explicitly rather than adopting the Poland identifiers.

```r
panel <- data.frame(
  province = c("A", "A", "B", "B"),
  year = c(2020, 2021, 2020, 2021),
  yield = c(40, 42, 38, 41),
  temperature_june = c(18, 20, 17, 19),
  rainfall_june = c(65, 40, 72, 48)
)
manifest <- data.frame(
  Term = c("temperature_june", "rainfall_june"),
  Variable = c("TMP", "PCP"),
  CalendarMonth = c(6, 6), AgriculturalPosition = c(1, 1)
)
data <- prepare_crop_data(panel, manifest,
  region = "province", year = "year", yield = "yield")
```

This small table illustrates the schema only; a chronological comparison requires at least twelve observed years. Optional positive area weights and independent national observations can also be supplied. Missing area weights produce equal-weight aggregation and this is recorded.

## Compare methods {#compare}

```r
config <- crop_model_config(
  methods = crop_model_methods(),
  stress_temperature = "MAX",
  stress_precipitation = "PCP",
  robust = TRUE
)
comparison <- compare_crop_models(barley, config,
  last_yield_year = 2018, predict_through = 2019)
summary(comparison)
plot(comparison)
```

The method is selected by minimum province-year **tuning** RMSE. Later evaluation scores are reported separately. In the website runs, initial history is 1999–2005, tuning is 2006–2011, and evaluation is 2012–2018. At each origin, coefficients and preprocessing are refitted using earlier yields; evaluation-period hyperparameters remain fixed.

`last_yield_year` controls the final fitting cutoff. Existing 2019 yields remain available as observations for plots, but do not enter fitting or tuning. The 2019 predictions use complete agricultural-year weather, so they are retrospective.

Choose a subset of methods for a faster comparison. Supply a named `grids` list to change the tuning candidates; document those choices before interpreting results.

## Predict and diagnose {#predict}

```r
selected <- get_crop_model(comparison)
future <- subset(barley$panel, Year == 2019)
predict(selected, future, interval = "prediction")
prediction_support(selected, future)

stress <- get_crop_model(comparison, "stress_lag")
explain_crop_prediction(stress, future)
coef(stress)
```

Prediction intervals are empirical 80% bands calibrated from tuning errors. They are available after comparison; direct `fit_crop_model()` does not independently calibrate them. National bands use national tuning errors rather than averaging provincial interval widths.

`prediction_support()` counts weather terms outside pooled training ranges and identifies unseen regions. `explain_crop_prediction()` supports stress-lag models and returns components in the response unit that sum to the prediction. Components are centred relative to training features; they are not causal attribution.

## Fit directly {#fit}

Use fixed parameters when tuning is not required:

```r
fictional <- synthetic_stress_example()
model <- fit_crop_model(fictional, "stress_lag",
  parameters = list(lambda = 1, smooth_ratio = 0,
    threshold = 0.75, temperature_variable = "TMP",
    precipitation_variable = "PCP"), robust = FALSE)
```

Direct fitting uses all finite responses in the supplied data. Mask or remove future yields first when a forecast-origin cutoff is required. The deterministic example has a declared nonlinear equation and provides a recovery test, not real-crop validation.

## Export and reproduce {#export}

```r
write_crop_results(comparison, "results/barley")
saveRDS(comparison, "results/barley/comparison.rds")
```

Exports include model metrics, row-level rolling and final predictions, candidate tuning scores, selected settings, coefficients, ensemble weights, prediction components, support diagnostics, configuration, fitted objects, plots, session information, and checksums. Existing artifacts require explicit `overwrite = TRUE`.

The website calculations can be reproduced with [run_poland_website.R](downloads/barley/run_poland_website.R): install YieldLag 0.2.0 and `jsonlite`, then run the script from a working directory with `Rscript run_poland_website.R barley` or `Rscript run_poland_website.R wheat`. The script uses the published package defaults and enables `MAX`/`PCP` compound terms. [Download the result tables](poland.html#downloads) to inspect the exact configuration and settings.

## Interpret results {#interpret}

RMSE, MAE and bias retain the yield unit; bias is prediction minus observation. Predictive R² is `1 − SSE/SST` and can be negative. Squared correlation measures association, not agreement. National scores and provincial scores describe different targets.

A flexible estimator need not beat a simpler model. The Poland runs show crop-dependent rankings, and tuning selection can differ from the best later-period result. Provincial errors are correlated by region and year; 112 province-years do not represent 112 independent experiments. See [validation assumptions](models.html#validation) and [data terms](citation.html).
'''
    guide = re.sub(r'\{#([^}]+)\}', '', guide) # Headings receive ids below.
    rendered = md(guide)
    for name, title in [('install','Install'),('data','Prepare data'),('compare','Compare methods'),('predict','Predict and diagnose'),('fit','Fit directly'),('export','Export and reproduce'),('interpret','Interpret results')]:
        rendered = re.sub(r'<h2 id="[^"]+">'+re.escape(title), f'<h2 id="{name}">'+title, rendered)
    write('guide.html', shell('User guide', hero('From installation to interpretation', 'A complete modelling workflow.', 'Prepare a regional panel, compare estimators, inspect predictions, and keep the results reproducible.')+layout(rendered, [('install','Install'),('data','Prepare data'),('compare','Compare methods'),('predict','Predict and diagnose'),('fit','Fit directly'),('export','Export and reproduce'),('interpret','Interpret results')]), 'Guide'))

    methods_intro = '''<h2 id="estimators">Eight complementary estimators</h2><div class="table-wrap"><table><thead><tr><th>Method</th><th>What it estimates</th></tr></thead><tbody>'''
    structures = ["Independent regional linear yield trends.", "The latest observed regional yield.", "Shared weather slopes with regional intercepts and trends.", "Separate regularized weather slopes within each region.", "Training-window principal components plus regional effects.", "Partially pooled regional departures from global seasonal effects.", "Linear and asymmetric anomaly responses, with optional hot–dry products.", "A non-negative, sum-to-one combination of the requested base estimators."]
    for (method, label), structure in zip(LABELS.items(), structures): methods_intro += f'<tr><td><code>{method}</code></td><td>{structure}</td></tr>'
    methods_intro += '</tbody></table></div>'
    model = (ROOT / 'docs/MODELS.md').read_text(encoding='utf-8')
    model = model[model.index('## Shared estimation'):]
    model = model.replace('The existing panel-ridge solver', 'The panel-ridge solver')
    model = model[:model.index('YieldLag uses penalized monthly hinge/product features.')]+ 'YieldLag implements penalized monthly hinge/product features motivated by these established nonlinear-response and distributed-lag ideas.\n'
    model = re.sub(r'(?m)^  https://(\S+)\.$', r'  [Read the study](https://\1).', model)
    rendered = methods_intro+md(model)
    validation = (ROOT / 'docs/VALIDATION.md').read_text(encoding='utf-8')
    validation = validation[validation.index('## Chronological design'):]
    validation = validation.replace('## ', '### ')
    rendered += '<h2 id="validation">Validation and interpretation</h2>'+md(validation)
    write('models.html', shell('Models and validation', hero('Statistical specification', 'Seasonal effects.<br>Explicit assumptions.', 'The equations, penalties, training rules, and interpretation limits behind every estimator.')+layout(rendered, [('estimators','Estimator overview'),('shared-estimation','Shared estimation'),('seasonal-stress-lag-basis','Stress-lag basis'),('prediction-interpretation','Prediction interpretation'),('ensemble-and-uncertainty','Ensemble and uncertainty'),('validation','Validation'),('references','References')]), 'Models'))

    poland = hero('Observed data · completed analysis', 'The Poland result explorer.', 'Two crops. Sixteen provinces. Eight methods.<br>Explore the actual calculations, including weak results and differences between tuning selection and later performance.')
    poland += '''<div class="wrap"><div class="tabs" role="tablist" aria-label="Crop"><button role="tab" data-crop="barley" aria-selected="true">Barley</button><button role="tab" data-crop="wheat" aria-selected="false">Wheat</button></div><div id="load-status" role="status" class="small"></div><div class="note" id="crop-summary">Barley: hierarchical modelling was selected by tuning RMSE. Its later province-year RMSE was 3.367 dt/ha. The lowest later score also belonged to hierarchical modelling.</div><div class="stats"><div class="stat"><strong>16</strong><span>Provinces</span></div><div class="stat"><strong>320</strong><span>Fitting yields through 2018</span></div><div class="stat"><strong>112</strong><span>Later evaluation province-years</span></div><div class="stat"><strong>7</strong><span>Later national observations</span></div></div>
<div class="timeline" aria-label="Chronological analysis periods"><div><strong>1999–2005</strong>Initial history</div><div><strong>2006–2011</strong>Tuning & calibration</div><div><strong>2012–2018</strong>Rolling evaluation</div><div><strong>2019</strong>Retrospective prediction</div></div><p class="small">Methods and hyperparameters are selected from tuning, not later rankings. Each rolling fit uses earlier responses. Full seasonal weather is available for each predicted year.</p></div>'''
    poland += '<section class="rule-section"><div class="wrap"><h2 id="performance">Compare later-period performance.</h2><p>All methods use the same years and inputs. Yield units are dt/ha (100 kg/ha). R² is predictive R²; interval coverage is observed coverage of empirical 80% bands.</p><div class="controls"><label for="metric-level">Evaluation target<select id="metric-level"><option>Province-year</option><option>National</option></select></label></div><div class="table-wrap" id="metrics-table">'+metric_table('barley')+'</div>'
    poland += figure(*FIGURES[1])+'</div></section>'
    poland += '''<section class="rule-section"><div class="wrap"><h2 id="predictions">Inspect the predictions.</h2><p>Switch methods or provinces. The observed 2019 yield is displayed for comparison but was excluded from model fitting. Earlier final-model fitted values are omitted from this chart.</p><div class="controls"><label for="chart-method">Method<select id="chart-method">'''+''.join(f'<option value="{m}"'+(' selected' if m=='hierarchical' else '')+f'>{label}</option>' for m,label in LABELS.items())+'''</select></label><label for="chart-region">Target<select id="chart-region"><option value="national">Area-weighted national</option></select></label></div><div class="plot-card"><h3 id="chart-title">Barley · Hierarchical · Area-weighted national</h3><div class="chart-legend"><span class="observed">Observation</span><span>Rolling prediction</span><span class="interval">Empirical 80% band</span><span class="future">2019 final prediction</span></div><div id="prediction-chart" aria-live="polite"><img src="assets/plots/barley/national_series.png" alt="Chronological barley national predictions for the tuning-selected hierarchical model"></div><p class="small">Shading separates tuning (2006–2011) and later evaluation (2012–2018). The 2019 marker uses the model fitted through 2018. Intervals share tuning-calibrated widths and do not adapt to local weather extrapolation.</p></div>'''+figure(*FIGURES[3])+figure(*FIGURES[0])+'''<h3>2019 predictions by province</h3><p class="small">Shown for the selected chart method. Errors are prediction minus observation; these 16 observations are not part of the 2012–2018 metric table.</p><div class="table-wrap" id="forecast-table"></div></div></section>'''
    poland += '<section class="rule-section"><div class="wrap"><h2 id="diagnostics">Where do errors occur?</h2><p>Inspect geographic differences, difficult years, and the trade-off between interval width and coverage.</p>'+figure(*FIGURES[4])+figure(*FIGURES[5])+figure(*FIGURES[6])+'</div></section>'
    poland += '<section class="rule-section"><div class="wrap"><h2 id="seasonal">What did the models learn?</h2><p>These figures describe final models fitted through 2018. They are not cross-validated effect estimates, and coefficients or decompositions do not establish causal responses.</p>'+figure(*FIGURES[7])+figure(*FIGURES[8])+figure(*FIGURES[9])+figure(*FIGURES[11])+'</div></section>'
    poland += '<section class="rule-section"><div class="wrap"><h2 id="support">How unusual was the 2019 weather?</h2>'+figure(*FIGURES[10])+'<h3>Selected parameters</h3><div class="table-wrap" id="parameter-table"></div></div></section>'
    poland += '''<section class="rule-section"><div class="wrap"><h2 id="downloads">Download and reproduce.</h2><div class="download-grid"><article class="card"><h3>Barley results</h3><p>All metric and prediction tables, tuning candidates, selected settings, coefficients, components, diagnostics, configuration, session information, and checksums.</p><a class="button small" href="downloads/barley-results.zip" download>Download ZIP</a> <a href="downloads/barley/metadata.json">Run metadata</a></article><article class="card"><h3>Wheat results</h3><p>The same complete export for wheat, using an agricultural year ending in July and identical evaluation years.</p><a class="button small" href="downloads/wheat-results.zip" download>Download ZIP</a> <a href="downloads/wheat/metadata.json">Run metadata</a></article></div><details><summary>Exact configuration and reproduction</summary><pre><code>install.packages(c("remotes", "jsonlite"))
remotes::install_github("MR-Eini/yieldlag", ref = "v0.2.0")

# Download run_poland_website.R, then from a terminal:
# Rscript run_poland_website.R barley
# Rscript run_poland_website.R wheat

# Configuration used in both runs:
config &lt;- crop_model_config(
  methods = crop_model_methods(),
  stress_temperature = "MAX",
  stress_precipitation = "PCP", robust = TRUE
)
# Package default grids, initial_fraction = 0.35,
# tuning_fraction = 0.30, interval_level = 0.80.</code></pre><p><a href="downloads/barley/run_poland_website.R">Download the R script</a>. Package source: v0.2.0, commit <code>29e1674</code>. Both runs retain all 84 terms and fit robustly where supported. Outputs preserve the full tuning grid rather than only its winning row.</p></details><div class="note warning" style="margin-top:25px"><strong>Interpretation limits.</strong> The national reference is constructed from provincial yields and fixed area weights. Monthly weather cannot resolve daily exposure, and solar-radiation units/derivation remain unspecified in the supplied tables. Tuning errors are reused for selection and interval calibration. The seven-year national evaluation is short, and these inspected study data are a development benchmark. Independent later data and issue-date weather inputs are needed for confirmatory or operational claims. <a href="citation.html">Data sources and terms</a>.</div><noscript><p>Interactive controls require JavaScript. All plots and downloadable tables remain available; open the wheat figures through its result files or use <a href="wheat.html">the static wheat report</a>.</p></noscript></div></section>'''
    poland = poland.replace('All metric and prediction tables, tuning candidates,', 'Complete fitted model objects, all metric and prediction tables, tuning candidates,')
    poland = poland.replace('The same complete export for wheat,', 'The same complete export, including fitted model objects, for wheat,')
    poland = re.sub(r'(<select id="[^"]+"|<button role="tab")', r'\1 disabled', poland)
    poland = poland.replace('<details><summary>Exact configuration and reproduction</summary>', '<details><summary>Read the saved model objects</summary><pre><code>library(yieldlag)\ncomparison &lt;- readRDS("barley/model_comparison.rds")\nsummary(comparison)\nmodel &lt;- get_crop_model(comparison)\nfuture &lt;- subset(comparison$prediction_panel, Year == 2019)\npredict(model, future, interval = "prediction")</code></pre><p>The ZIP contains the full comparison and fitted model list. Input provenance uses portable package-relative references.</p></details><details><summary>Exact configuration and reproduction</summary>')
    write('poland.html', shell('Poland results', poland, 'Poland example', scripts=('assets/poland.js',)))
    # Complete static alternatives make all results accessible without JavaScript.
    for crop in ['barley','wheat']:
        content = hero('Static result report', f'Poland · {crop.title()}', 'Complete scientific figures and later-period scores, with no JavaScript required.')
        content += '<div class="wrap"><h2>Province-year evaluation</h2><div class="table-wrap">'+metric_table(crop)+'</div><h2>National evaluation</h2><div class="table-wrap">'+metric_table(crop,'National')+'</div>'
        content += ''.join(figure(name,title,caption,crop) for name,title,caption in FIGURES)
        content += f'<div class="actions"><a class="button" href="downloads/{crop}-results.zip">Download complete tables</a><a class="button secondary" href="poland.html">Interactive explorer</a></div><p class="small" style="margin:25px 0">Retrospective benchmark; fixed area weights and complete seasonal weather. National evaluation contains seven annual observations.</p></div>'
        write(crop+'.html', shell('Poland · '+crop.title(),content,'Poland example'))

    citation = '<h2 id="software">Cite the software</h2><p>Maintainer and author: <strong>Mohammad Reza Eini</strong>. Use <code>citation("yieldlag")</code> in R.</p><p>Eini, M. R. (2026). <em>YieldLag: Seasonal Climate Responses and Regional Crop Yield Modelling</em>. R package version 0.3.0. <a href="https://github.com/MR-Eini/yieldlag">GitHub repository</a>.</p><h2 id="study">Study context</h2><p>The Poland data setting is described by Eini, Conradt, and Piniewski (2026), <em>Theoretical and Applied Climatology</em>, <a href="https://doi.org/10.1007/s00704-026-06322-8">doi:10.1007/s00704-026-06322-8</a>. Website results are newly computed with YieldLag 0.2.0 and its documented comparison procedure; they are not a claim to reproduce the paper’s historical metrics.</p><h2 id="data">Data specification</h2>'
    data = (ROOT/'docs/DATA.md').read_text(encoding='utf-8')
    data = data[data.index('## Poland example'):].replace('## ','### ')
    data = data[:data.index('[Data attribution]')]
    citation += md(data)+'<h2 id="terms">Data attribution and terms</h2>'
    terms = (ROOT/'inst/extdata/poland/DATA_LICENSE.md').read_text(encoding='utf-8')
    citation += md('\n'.join(terms.splitlines()[1:]))
    citation += '<h2 id="license">Software license</h2>'+md((ROOT/'LICENSE.md').read_text(encoding='utf-8'))
    write('citation.html', shell('Citation, data and license', hero('Sources & attribution', 'Know what you are using.', 'Software citation, the provenance of the Poland example, and the distinct terms that accompany code and data.')+layout(citation,[('software','Software citation'),('study','Study context'),('data','Data specification'),('terms','Data terms'),('license','Software license')]),''))

    topics = []
    for source in sorted((ROOT/'outputs/website_reference').glob('*.html')):
        raw = source.read_text(encoding='utf-8')
        title = re.search(r'<h2>(.*?)</h2>',raw,re.S).group(1)
        main = re.search(r'<main>(.*?)</main>',raw,re.S).group(1)
        # Replace package links and link standard R topics to the R manuals.
        main = re.sub(r'href="(?:\.\./)+([^/]+)/html/([^"#]+)"', r'href="https://stat.ethz.ch/R-manual/R-release/library/\1/html/\2"', main)
        main = re.sub(r'<table style="width: 100%;">.*?</table>', '', main, count=1, flags=re.S)
        main = main.replace('<h2>', '<h1 style="font-size:2.8rem">',1).replace('</h2>','</h1>',1)
        topics.append((source.stem,title))
        content = '<div class="wrap content-layout"><aside class="toc"><a href="index.html">← All reference topics</a><a href="../guide.html">User guide</a><a href="../models.html">Model specification</a></aside><article class="prose reference-body">'+main+'</article></div>'
        write('reference/'+source.name, shell(source.stem, content, 'Reference', prefix='../'))
    reference = hero('Function-level documentation', 'The R reference.', 'Arguments, return values, and examples generated from the help files shipped with YieldLag 0.3.0.')
    reference += '<div class="wrap" style="padding-bottom:70px"><label for="api-search" class="eyebrow">Find a function or topic</label><input id="api-search" type="search" placeholder="Search predictions, data, models…" style="width:min(600px,100%);margin-top:12px"><span id="api-count" class="small" role="status" style="display:block;margin:10px 0">'+str(len(topics))+' topics</span><div class="api-list">'
    reference += ''.join(f'<article class="api-item"><a href="{name}.html">{name}</a><p>{title}</p></article>' for name,title in topics)
    reference += '</div></div>'
    write('reference/index.html', shell('Function reference', reference, 'Reference', prefix='../'))
    # hero/reference links and assets need the same prefix as the shared shell.
    path=SITE/'reference/index.html'
    text=path.read_text(encoding='utf-8')
    path.write_text(text,encoding='utf-8',newline='\n')
    write('404.html', shell('Page not found',hero('404','This page could not be found.','Return to the <a href="https://mr-eini.github.io/yieldlag/">YieldLag homepage</a>.'),''))
    write('.nojekyll','')
    print(f'Built documentation site with {len(topics)} R reference topics and two complete Poland reports.')

if __name__ == '__main__': build()
