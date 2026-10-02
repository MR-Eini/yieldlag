"""Render scientific figures and browser data from the saved Poland runs.

Dependencies: numpy, pandas, matplotlib. No models are fitted here.
Run from the repository root after analysis/run_poland_website.R.
"""
from pathlib import Path
import csv
import hashlib
import json
import zipfile
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap, TwoSlopeNorm

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
METHODS = ["trend", "persistence", "panel_ridge", "local_ridge", "pcr",
           "hierarchical", "stress_lag", "ensemble"]
LABELS = dict(zip(METHODS, ["Trend", "Persistence", "Panel ridge", "Local ridge",
                          "PCR", "Hierarchical", "Stress lag", "Ensemble"]))
GREEN, GOLD, INK = "#21624d", "#b7791f", "#20332d"
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.labelcolor": INK, "text.color": INK, "axes.titleweight": "bold",
    "figure.facecolor": "white", "savefig.facecolor": "white",
    "svg.fonttype": "none"})

FIGURES = [
 ("yield_history", "Observed yields", "Provincial yield histories and the fixed-area weighted national reference. The 2019 observations are excluded from model fitting."),
 ("model_comparison", "Later-period performance", "RMSE in 2012–2018. Green marks the method selected using earlier tuning; gold highlights stress lag when it is not the selected method. National scores have only seven annual observations."),
 ("national_series", "Chronological national predictions", "The tuning-selected method, rolling predictions, and empirical 80% bands. The 2019 point comes from the final model fitted through 2018; it is a retrospective prediction using complete seasonal weather."),
 ("province_scatter", "Observed versus predicted", "All eight methods on the same 112 later-period province-years. The dashed line is perfect agreement; each panel reports predictive R², which can be negative."),
 ("regional_rmse", "Performance by province", "Later-period RMSE for every province and method. Each province contributes seven evaluation years; colour differences are descriptive, without uncertainty intervals."),
 ("yearly_rmse", "Performance by year", "RMSE across 16 provinces for each evaluation year. Shared adverse years can make province errors spatially correlated."),
 ("intervals", "Interval coverage and width", "Coverage and mean width of tuning-calibrated empirical 80% bands in the later period. The dashed line is the nominal target, not a guaranteed coverage level."),
 ("seasonal_coefficients", "Seasonal weather coefficients", "Final panel-ridge and hierarchical global coefficients, per training-standardized weather term. Months follow the agricultural year. Associations are not causal effects."),
 ("stress_basis", "Nonlinear seasonal basis", "Final stress-lag coefficients for linear anomalies, upper/lower tails, and hot–dry products. Each expanded feature is training-standardized; colour scales differ between panels."),
 ("components_2019", "2019 stress prediction components", "The upper panel shows intercept, trend and regional baseline; the lower panel separates centred weather and AR contributions. Adding both panels gives the stress-lag prediction. Tail components can be nonzero when raw hinges are zero."),
 ("support_2019", "2019 weather support", "Count of raw monthly terms outside pooled training minima/maxima in 1999–2018. All methods share these input ranges. Zero flags does not establish support of every joint weather combination."),
 ("ensemble_weights", "Ensemble weights", "Non-negative weights summing to one, learned from the tuning period. These are fitted weights, not probabilities that a method is correct.")
]

def records(frame):
    return json.loads(frame.to_json(orient="records", force_ascii=False, double_precision=12))

def render(crop):
    folder = ROOT / "outputs/website_poland" / crop
    out = SITE / "assets/plots" / crop
    out.mkdir(parents=True, exist_ok=True)
    metadata = json.loads((folder / "metadata.json").read_text(encoding="utf-8"))
    tables = {p.stem: pd.read_csv(p, dtype={"RS": str}) for p in folder.glob("*.csv")}
    names = dict(zip(tables["region_names"].RS, tables["region_names"].Region.str.title()))
    regions = sorted(names)
    assert len(regions) == 16
    selected = metadata["selected_method"]
    metrics = tables["model_metrics"]
    cv = tables["province_cv_predictions"]
    evaluation = cv[cv.Phase == "evaluation"]

    def save(fig, name):
        fig.suptitle(f"Poland · {crop.title()}", fontsize=14, x=.02, ha="left", fontweight="bold")
        fig.tight_layout(rect=[0, 0, 1, .94])
        fig.savefig(out / (name + ".png"), dpi=170, bbox_inches="tight")
        fig.savefig(out / (name + ".svg"), bbox_inches="tight")
        plt.close(fig)

    panel = tables["input_panel"]
    fig, ax = plt.subplots(figsize=(11, 5))
    for rs, part in panel[panel.Year >= 1999].groupby("RS"):
        ax.plot(part.Year, part[".yield"], color="#aebfb7", alpha=.7, lw=1)
    area = tables["area_weights"].set_index("RS").Area
    observed = panel[panel.Year >= 1999].copy()
    observed["weight"] = observed.RS.map(area)
    national = observed.groupby("Year").apply(lambda p: np.average(p[".yield"], weights=p.weight), include_groups=False)
    ax.plot(national.index, national, lw=2.8, color=GREEN, label="Fixed-area weighted reference")
    ax.axvspan(2005.5, 2011.5, color="#f6edcc", alpha=.5, label="Tuning")
    ax.axvspan(2011.5, 2018.5, color="#dfeee5", alpha=.45, label="Evaluation")
    ax.set(xlabel="Harvest year", ylabel="Yield (dt/ha)", title="Observed provincial yields")
    ax.legend(frameon=False, fontsize=9, ncol=3)
    save(fig, "yield_history")

    fig, axes = plt.subplots(1, 2, figsize=(12, 5))
    for ax, level in zip(axes, ["Province-year", "National"]):
        part = metrics[metrics.Level == level].sort_values("RMSE", ascending=False)
        colours = [GREEN if m == selected else GOLD if m == "stress_lag" else "#b8c6bf" for m in part.Method]
        ax.barh([LABELS[m] for m in part.Method], part.RMSE, color=colours)
        for i, value in enumerate(part.RMSE): ax.text(value+.05, i, f"{value:.2f}", va="center", fontsize=9)
        ax.set(xlabel="RMSE (dt/ha) · lower is better", title=level, xlim=(0, part.RMSE.max()*1.19))
    save(fig, "model_comparison")

    ncv = tables["national_cv_predictions"]
    national = ncv[ncv.Method == selected].sort_values("Year")
    future = tables["national_predictions"]
    future = future[(future.Method == selected) & (future.Year == 2019)]
    plotted = pd.concat([national, future]).sort_values("Year")
    fig, ax = plt.subplots(figsize=(11, 5))
    ax.axvspan(2005.5, 2011.5, color="#f6edcc", alpha=.5)
    ax.axvspan(2011.5, 2018.5, color="#dfeee5", alpha=.4)
    ax.fill_between(plotted.Year, plotted.Lower80Weighted, plotted.Upper80Weighted, color=GREEN, alpha=.13, label="Empirical 80% band")
    ax.plot(plotted.Year, plotted.ObservedWeighted, "o-", color=INK, label="Weighted observation")
    ax.plot(national.Year, national.PredictedWeighted, "o-", color=GREEN, label=LABELS[selected])
    ax.scatter(future.Year, future.PredictedWeighted, marker="D", color=GOLD, s=70, label="2019 retrospective prediction", zorder=5)
    ax.axvline(2018.5, ls=":", color="#7c8a82")
    ax.set(xlabel="Harvest year", ylabel="Yield (dt/ha)", title=f"Tuning-selected method: {LABELS[selected]}")
    ax.legend(frameon=False, ncol=2, fontsize=9)
    save(fig, "national_series")

    fig, axes = plt.subplots(2, 4, figsize=(13, 7), sharex=True, sharey=True)
    lim = [min(evaluation.Observed.min(), evaluation.Predicted.min())-2,
           max(evaluation.Observed.max(), evaluation.Predicted.max())+2]
    for ax, method in zip(axes.flat, METHODS):
        part = evaluation[evaluation.Method == method]
        metric = metrics[(metrics.Method == method) & (metrics.Level == "Province-year")].iloc[0]
        ax.scatter(part.Observed, part.Predicted, s=17, alpha=.65, c=part.Year, cmap="viridis", vmin=2012, vmax=2018)
        ax.plot(lim, lim, ls="--", color="#7c8a82", lw=1)
        ax.set(xlim=lim, ylim=lim, title=f"{LABELS[method]}\nRMSE {metric.RMSE:.2f}; R² {metric.R2:.2f}")
        ax.set_xlabel("Observed (dt/ha)"); ax.set_ylabel("Predicted (dt/ha)")
    save(fig, "province_scatter")

    fig, ax = plt.subplots(figsize=(11, 7))
    regional = tables["metrics_by_region"].pivot(index="RS", columns="Method", values="RMSE").reindex(index=regions, columns=METHODS)
    image = ax.imshow(regional, cmap="YlGn", aspect="auto")
    ax.set_yticks(range(len(regions)), [names[r] for r in regions])
    ax.set_xticks(range(len(METHODS)), [LABELS[m] for m in METHODS], rotation=35, ha="right")
    for i in range(len(regions)):
        for j in range(len(METHODS)): ax.text(j, i, f"{regional.iloc[i,j]:.1f}", ha="center", va="center", fontsize=8, color="white" if regional.iloc[i,j] > np.nanmax(regional.values)*.65 else INK)
    fig.colorbar(image, ax=ax, label="RMSE (dt/ha)")
    ax.set_title("Later-period RMSE by province")
    save(fig, "regional_rmse")

    fig, ax = plt.subplots(figsize=(11, 5))
    yearly = tables["metrics_by_year"]
    for method in METHODS:
        part = yearly[yearly.Method == method].sort_values("Year")
        ax.plot(part.Year, part.RMSE, "o-", lw=2.6 if method == selected else 1.4, label=LABELS[method])
    ax.set(xlabel="Evaluation year", ylabel="RMSE across provinces (dt/ha)", title="Year-to-year variation in error")
    ax.legend(frameon=False, ncol=4, fontsize=9)
    save(fig, "yearly_rmse")

    fig, axes = plt.subplots(2, 2, figsize=(12, 8))
    for row_index, level in enumerate(["Province-year", "National"]):
        part = metrics[metrics.Level == level].set_index("Method").reindex(METHODS)
        positions = np.arange(len(METHODS))
        colours = [GREEN if method == selected else GOLD if method == "stress_lag" else "#899f93" for method in METHODS]
        coverage, width = axes[row_index]
        coverage.scatter(part.Coverage80*100, positions, s=65, color=colours)
        coverage.axvline(80, ls="--", color=INK, lw=1)
        coverage.set(xlabel="Observed coverage (%)", title=level+" · coverage", xlim=(0, 110))
        width.barh(positions, part.MeanWidth80, color=colours)
        width.set(xlabel="Mean interval width (dt/ha)", title=level+" · width", xlim=(0, part.MeanWidth80.max()*1.2))
        for ax in (coverage, width):
            ax.set_yticks(positions, [LABELS[method] for method in METHODS])
            ax.invert_yaxis()
        for i, (_, item) in enumerate(part.iterrows()):
            coverage.text(item.Coverage80*100+2, i, f"{item.Coverage80*100:.1f}", va="center", fontsize=8)
            width.text(item.MeanWidth80+.15, i, f"{item.MeanWidth80:.1f}", va="center", fontsize=8)
    save(fig, "intervals")

    coefficients = tables["monthly_coefficients"]
    variables = list(coefficients.Variable.unique())
    fig, axes = plt.subplots(2, 4, figsize=(13, 7))
    for ax, variable in zip(axes.flat, variables):
        for method, part in coefficients[coefficients.Variable == variable].groupby("Method"):
            part = part.sort_values("AgriculturalPosition")
            ax.plot(part.AgriculturalPosition, part.StandardizedEstimate, "o-", markersize=3, label=LABELS[method], color=GREEN if method == "hierarchical" else GOLD)
        ax.axhline(0, color="#acb7b1", lw=.8)
        ax.set_xticks(part.AgriculturalPosition, [f"{int(m):02d}" for m in part.CalendarMonth], rotation=45, fontsize=8)
        ax.set(title=variable, xlabel="Calendar month in seasonal order", ylabel="Coefficient (dt/ha)")
    axes.flat[-1].axis("off")
    axes.flat[-1].legend(*axes.flat[0].get_legend_handles_labels(), loc="center", frameon=False)
    save(fig, "seasonal_coefficients")

    stress = tables["stress_basis_coefficients"]
    fig, axes = plt.subplots(2, 2, figsize=(13, 8))
    diverging = LinearSegmentedColormap.from_list("yieldlag", ["#b36a35", "#f7f8f4", GREEN])
    for ax, component in zip(axes.flat, ["linear", "upper_tail", "lower_tail", "compound_hot_dry"]):
        part = stress[stress.Component == component].copy()
        part["WeatherVariable"] = part.Variable.str.replace(component+"__", "", regex=False)
        if component == "compound_hot_dry": part["WeatherVariable"] = "MAX × PCP"
        matrix = part.pivot(index="WeatherVariable", columns="AgriculturalPosition", values="Coefficient")
        bound = max(abs(matrix.values).max(), .001)
        image = ax.imshow(matrix, cmap=diverging, aspect="auto", vmin=-bound, vmax=bound)
        monthmap = part.drop_duplicates("AgriculturalPosition").set_index("AgriculturalPosition").CalendarMonth
        ax.set_xticks(range(len(matrix.columns)), [f"{int(monthmap[p]):02d}" for p in matrix.columns], fontsize=8)
        ax.set_yticks(range(len(matrix.index)), matrix.index)
        ax.set(title=component.replace("_", " ").title(), xlabel="Calendar month in seasonal order")
        fig.colorbar(image, ax=ax, label="Standardized-basis coefficient (dt/ha)", shrink=.8)
    save(fig, "stress_basis")

    components = tables["stress_components_2019"].set_index("RS").reindex(regions)
    fig, axes = plt.subplots(2, 1, figsize=(13, 8), sharex=True)
    baseline = components.Intercept + components.Trend + components.Regional
    axes[0].bar(np.arange(len(regions)), baseline, color="#b8c6bf", label="Intercept + trend + region")
    axes[0].scatter(np.arange(len(regions)), components.Prediction, color=GREEN, label="Complete stress prediction", zorder=5)
    axes[0].set(ylabel="Yield (dt/ha)", title="Baseline and complete prediction")
    axes[0].legend(frameon=False, ncol=2, fontsize=9)
    colours = [GREEN, "#93b18b", GOLD, "#9c5540", "#6f7f9d"]
    positive, negative = np.zeros(len(regions)), np.zeros(len(regions))
    for term, colour in zip(["LinearAnomaly", "UpperTail", "LowerTail", "HotDry", "ARCorrection"], colours):
        values = components[term].values
        bottom = np.where(values >= 0, positive, negative)
        axes[1].bar(np.arange(len(regions)), values, bottom=bottom, color=colour, label=term)
        positive += np.maximum(values, 0); negative += np.minimum(values, 0)
    axes[1].axhline(0, color=INK, lw=.8)
    axes[1].set_xticks(range(len(regions)), [names[r] for r in regions], rotation=50, ha="right", fontsize=8)
    axes[1].set(ylabel="Contribution (dt/ha)", title="Centred weather and residual contributions")
    axes[1].legend(frameon=False, ncol=5, fontsize=8)
    save(fig, "components_2019")

    support = tables["support_2019"]
    support = support[support.Method == selected].set_index("RS").reindex(regions)
    fig, ax = plt.subplots(figsize=(11, 6))
    ax.barh([names[r] for r in regions], support.OutsideTerms, color=GOLD)
    for i, (_, row) in enumerate(support.iterrows()): ax.text(row.OutsideTerms+.15, i, f"{int(row.OutsideTerms)} / {int(row.TotalTerms)}", va="center", fontsize=9)
    ax.set(xlabel="Monthly weather terms outside training ranges", title="2019 marginal weather extrapolation", xlim=(0, max(support.OutsideTerms.max()+3, 5)))
    save(fig, "support_2019")

    weights = tables["ensemble_weights"]
    fig, ax = plt.subplots(figsize=(10, 4))
    ax.bar([LABELS[m] for m in weights.Method], weights.Weight, color=[GOLD if m == "stress_lag" else GREEN for m in weights.Method])
    ax.set(ylabel="Tuning-fitted weight", title="Non-negative ensemble composition", ylim=(0, max(.5, weights.Weight.max()*1.18)))
    ax.tick_params(axis="x", rotation=25)
    save(fig, "ensemble_weights")

    # CSVs and configuration are enough to independently inspect all displayed results.
    # Public exports use relative input labels rather than workstation paths.
    downloads = SITE / "downloads" / crop
    downloads.mkdir(parents=True, exist_ok=True)
    exports = ["model_metrics", "method_selection_tuning", "all_tuning_results",
        "selected_hyperparameters", "metrics_by_region", "metrics_by_year",
        "province_cv_predictions", "national_cv_predictions", "province_predictions",
        "national_predictions", "monthly_coefficients", "stress_basis_coefficients",
        "stress_components_2019", "support_2019", "ensemble_weights",
        "weather_feature_manifest", "area_weights", "region_names"]
    for stem in exports: tables[stem].to_csv(downloads / (stem+".csv"), index=False, encoding="utf-8")
    (downloads / "metadata.json").write_text(json.dumps(metadata, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    (downloads / "analysis_config.dput").write_bytes((folder / "analysis_config.dput").read_bytes())
    (downloads / "session_info.txt").write_bytes((folder / "session_info.txt").read_bytes())
    (downloads / "run_poland_website.R").write_bytes((ROOT / "analysis/run_poland_website.R").read_bytes())
    hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in downloads.iterdir() if p.is_file() and p.name != "SHA256SUMS.txt"}
    (downloads / "SHA256SUMS.txt").write_text("".join(f"{digest}  {name}\n" for name, digest in sorted(hashes.items())), encoding="utf-8")
    with zipfile.ZipFile(SITE / "downloads" / (crop+"-results.zip"), "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(downloads.iterdir()): archive.write(path, arcname=crop+"/"+path.name)
    return {"metadata": metadata, "region_names": names,
            **{key: records(tables[key]) for key in ["model_metrics", "method_selection_tuning",
                "national_cv_predictions", "national_predictions", "province_cv_predictions",
                "province_predictions", "stress_components_2019", "support_2019",
                "selected_hyperparameters", "ensemble_weights"]}}

if __name__ == "__main__":
    payload = {crop: render(crop) for crop in ["barley", "wheat"]}
    (SITE / "assets/data").mkdir(parents=True, exist_ok=True)
    (SITE / "assets/data/poland.json").write_text(json.dumps(payload, ensure_ascii=False, allow_nan=False, separators=(",", ":")), encoding="utf-8")
    print("Rendered 24 scientific figures in PNG and SVG; exported results and browser data.")
