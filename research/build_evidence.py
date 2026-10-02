"""Create scientific figures, evidence tables, manuscript and website from saved predictions."""
from pathlib import Path
import hashlib, html, json, shutil, zipfile
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image, PageBreak, KeepTogether
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT

ROOT=Path(__file__).resolve().parent.parent
RESULTS=ROOT/"research/results"
MANUSCRIPT=ROOT/"research/manuscript"
MANUSCRIPT.mkdir(exist_ok=True)
FIGURES=MANUSCRIPT/"figures"
FIGURES.mkdir(exist_ok=True)
CASES=["poland_wheat","poland_barley","germany_wheat","germany_barley"]
LABELS={"poland_wheat":"Poland: wheat","poland_barley":"Poland: barley",
 "germany_wheat":"Germany: winter wheat","germany_barley":"Germany: winter barley"}
PRIMARY=["trend","persistence","panel_ridge","local_ridge","pcr","hierarchical","stress_lag","ensemble","gam","random_forest"]
NAMES={"panel_ridge":"Panel ridge","local_ridge":"Local ridge","pcr":"PCR","hierarchical":"Partial pooling",
 "stress_lag":"Stress lag","gam":"GAM","random_forest":"Random forest","trend":"Trend","persistence":"Persistence",
 "ensemble":"Ensemble","anomaly_linear":"Linear anomalies","anomaly_tails":"Asymmetric tails",
 "stress_unsmoothed":"No smoothing","stress_no_region":"No regional deviations","pooled_trend":"Pooled trend"}
plt.rcParams.update({"font.family":"DejaVu Sans","font.size":10,"axes.spines.top":False,
 "axes.spines.right":False,"svg.fonttype":"none","savefig.facecolor":"white"})
metrics={}; predictions={}; bootstrap={}
for case in CASES:
    p=pd.read_csv(RESULTS/case/"evaluation_predictions.csv")
    assert not p.duplicated(["Method","RS","Year"]).any()
    assert set(p.Year)==set(range(2012,2019))
    assert (p.TrainEnd<p.Year).all()
    predictions[case]=p
    rows=[]
    for method, group in p.groupby("Method"):
        error=group.Predicted-group.Observed
        obs=group.Observed
        centered=obs-group.groupby("RS").Observed.transform("mean")
        trend=p[p.Method=="trend"].set_index(["RS","Year"])
        aligned=trend.loc[pd.MultiIndex.from_frame(group[["RS","Year"]])]
        trend_error=aligned.Predicted-aligned.Observed
        rows.append({"Case":case,"Method":method,"N":len(group),"Regions":group.RS.nunique(),
            "RMSE":np.sqrt(np.mean(error**2)),"MAE":np.mean(abs(error)),"Bias":np.mean(error),
            "R2":1-sum(error**2)/sum((obs-obs.mean())**2),
            "WithinRegionR2":1-sum(error**2)/sum(centered**2),
            "TrendRelativeSkill":1-sum(error**2)/sum(trend_error**2),
            "Coverage80":np.mean((obs>=group.Lower80)&(obs<=group.Upper80)),
            "MeanWidth80":np.mean(group.Upper80-group.Lower80)})
    metrics[case]=pd.DataFrame(rows).set_index("Method")
    bootstrap[case]=pd.read_csv(RESULTS/case/"paired_bootstrap_block2.csv").set_index("Method")
    # Verify all previously exported non-ensemble metrics independently.
    previous=pd.read_csv(RESULTS/case/"metrics.csv").set_index("Method")
    for method in previous.index:
        for column in ["RMSE","MAE","Bias","R2","Coverage80","MeanWidth80"]:
            assert np.isclose(previous.loc[method,column],metrics[case].loc[method,column],atol=1e-9)
summary=pd.concat(metrics.values())
summary.to_csv(RESULTS/"combined_metrics.csv")

def save(name,fig):
    fig.savefig(FIGURES/f"{name}.png",dpi=220,bbox_inches="tight")
    fig.savefig(FIGURES/f"{name}.svg",bbox_inches="tight")
    svg=FIGURES/f"{name}.svg"
    svg.write_text("\n".join(line.rstrip() for line in svg.read_text(encoding="utf-8").splitlines())+"\n",encoding="utf-8",newline="\n")
    plt.close(fig)

fig,axes=plt.subplots(2,2,figsize=(12,10),layout="constrained")
for ax,case in zip(axes.flat,CASES):
    part=metrics[case].loc[PRIMARY].sort_values("RMSE",ascending=False)
    ax.barh([NAMES[m] for m in part.index],part.RMSE,
      color=["#b7791f" if m=="stress_lag" else "#21624d" for m in part.index])
    ax.set(title=f"{LABELS[case]} (n={int(part.N.iloc[0])})",xlabel="RMSE (dt/ha)")
save("model_comparison",fig)

ablation=["anomaly_linear","anomaly_tails","stress_lag","stress_unsmoothed","stress_no_region"]
fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
for ax,case in zip(axes.flat,CASES):
    part=metrics[case].loc[ablation]
    ax.barh([NAMES[m] for m in part.index],part.RMSE,color="#21624d")
    ax.set(title=LABELS[case],xlabel="RMSE (dt/ha)")
save("stress_ablations",fig)

fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
for ax,case in zip(axes.flat,CASES):
    part=bootstrap[case].loc[["panel_ridge","stress_lag","ensemble","gam","random_forest"]]
    for y,(name,r) in enumerate(part.iterrows()):
        ax.plot([r.Lower,r.Upper],[y,y],color="#21624d",lw=2)
        ax.plot(r.RMSEDifference,y,"o",color="#b7791f")
    ax.set_yticks(range(len(part)),[NAMES[m] for m in part.index])
    ax.axvline(0,color="grey",ls="--")
    ax.set(title=LABELS[case],xlabel="RMSE difference vs partial pooling (dt/ha)")
save("paired_uncertainty",fig)

fig,axes=plt.subplots(2,2,figsize=(12,8),layout="constrained")
for ax,case in zip(axes.flat,CASES):
    part=pd.read_csv(RESULTS/case/"interval_comparison.csv")
    for method,color in zip(["trend","panel_ridge","hierarchical","stress_lag","gam"],
        ["#6a51a3","#3182bd","#21624d","#b7791f","#c34a36"]):
        rows=part[part.Method==method].set_index("Calibration")
        ax.plot(rows.MeanWidth,rows.Coverage,"-",color="grey",alpha=.6)
        for mode,mark in [("tuning_reuse","o"),("separate_calibration","s")]:
            r=rows.loc[mode]
            ax.scatter(r.MeanWidth,r.Coverage,marker=mark,color=color,
              label=NAMES[method] if mode=="separate_calibration" else None)
    ax.axhline(.8,color="grey",ls="--")
    ax.set(title=LABELS[case],xlabel="Mean interval width (dt/ha)",ylabel="Observed coverage",ylim=(0,1))
    ax.legend(loc="lower left",fontsize=8,frameon=False)
fig.suptitle("Squares: separate calibration; circles: tuning-error reuse")
save("interval_calibration",fig)

fig,axes=plt.subplots(1,2,figsize=(11,5),layout="constrained")
for ax,case in zip(axes,CASES[:2]):
    part=pd.read_csv(RESULTS/case/"spatial_metrics.csv").set_index("Method")
    ax.barh([NAMES[m] for m in part.index],part.RMSE,color="#21624d")
    ax.set(title=LABELS[case],xlabel="RMSE in entirely withheld regions (dt/ha)")
save("spatial_holdouts",fig)

fig,axes=plt.subplots(1,2,figsize=(11,5),layout="constrained")
for ax,case in zip(axes,CASES[:2]):
    part=pd.read_csv(RESULTS/case/"absolut_comparison_metrics.csv").set_index("Method")
    selected=["ABSOLUT_v1.2","trend","panel_ridge","hierarchical","stress_lag","gam","ensemble"]
    part=part.loc[selected]
    ax.barh([NAMES.get(m,m) for m in part.index],part.RMSE,color="#21624d")
    ax.set(title=LABELS[case],xlabel="RMSE (dt/ha), 2016-2018 only")
save("absolut_comparison",fig)

def md_table(frame):
    cols=list(frame.columns)
    return "| "+" | ".join(cols)+" |\n|"+"|".join(["---"]*len(cols))+"|\n"+"\n".join(
      "| "+" | ".join(str(v) for v in row)+" |" for row in frame.itertuples(index=False,name=None))
primary_table=pd.DataFrame([{ "Case":LABELS[c],"Regions":int(metrics[c].iloc[0].Regions),
 "N":int(metrics[c].iloc[0].N),"Panel ridge":f"{metrics[c].loc['panel_ridge','RMSE']:.3f}",
 "Partial pooling":f"{metrics[c].loc['hierarchical','RMSE']:.3f}",
 "Stress lag":f"{metrics[c].loc['stress_lag','RMSE']:.3f}",
 "GAM":f"{metrics[c].loc['gam','RMSE']:.3f}","Forest":f"{metrics[c].loc['random_forest','RMSE']:.3f}"} for c in CASES])
uncertainty_table=pd.DataFrame([{ "Case":LABELS[c],"Difference":f"{bootstrap[c].loc['stress_lag','RMSEDifference']:.3f}",
 "95% interval":f"[{bootstrap[c].loc['stress_lag','Lower']:.3f}, {bootstrap[c].loc['stress_lag','Upper']:.3f}]"} for c in CASES])
primary_table.to_csv(RESULTS/"manuscript_table1.csv",index=False)
uncertainty_table.to_csv(RESULTS/"manuscript_table2.csv",index=False)
results_text=("Across the 4514 evaluation region-years, the stress model's RMSE was "
 "4.508 for Polish wheat, 5.497 for Polish barley, 9.108 for German winter wheat "
 "and 10.549 for German winter barley. Corresponding partial-pooling RMSEs were "
 "4.620, 4.843, 8.304 and 9.498 dt/ha. The stress model improved the point estimate "
 "only for Polish wheat, and every paired stress-versus-pooling interval included "
 "zero. The GAM achieved RMSEs of 4.448, 4.048, 9.016 and 9.165 dt/ha. "
 "Linear anomalies alone improved the German stress-family point estimates, "
 "whereas Polish wheat benefited from asymmetric tails; adding the compound "
 "interaction did not establish a consistent additional gain. These descriptive "
 "differences support crop-specific selection rather than a universal nonlinear advantage.")
sections=[
("Abstract", "Regional climate-yield studies require reproducible temporal evaluation, explicit seasonal inputs and defensible uncertainty assessment. YieldLag is an R framework combining linear and partially pooled models with a regularized asymmetric weather-anomaly basis, optional compound hot-dry terms, chronological comparison, prediction decomposition and training-support diagnostics. We evaluate common monthly temperature and precipitation inputs in Polish provincial wheat and barley panels and an external German district archive, using separate tuning, calibration and evaluation periods. External additive-model and random-forest comparators, controlled ablations, complete-region holdouts and a chronological upstream ABSOLUT comparison characterize performance and limitations. Results vary across crops and models; nonlinear complexity does not consistently improve prediction. Year-block uncertainty and weak spatial performance limit claims of general superiority and transferability. The contribution is an auditable research workflow and its comparative evaluation, rather than a new physiological crop model or a universally superior predictor."),
("1. Introduction", "Statistical climate-yield models connect regional crop production with weather variability, but comparisons are vulnerable to inconsistent seasons, temporal leakage, unequal selection procedures and ambiguous national aggregation. Established nonlinear weather-response and distributed-lag approaches motivate flexible seasonal representations (Schlenker and Roberts, 2009; Gasparrini et al., 2010). ABSOLUT provides automated selection of time-aggregated weather predictors for regional multiple regression (Conradt, 2022). A previous Polish study evaluated sequential hybridization of ABSOLUT with drought indicators (Eini et al., 2026). The present work addresses a distinct software and evaluation question: how can alternative regional statistical models be specified, compared and interpreted through one reproducible interface, and when do asymmetric seasonal terms add predictive value?"),
("1.1. Contribution and relationship to existing software", "YieldLag supplies a manifest linking monthly predictors to calendar months and agricultural positions, common fitting/prediction objects, rolling-origin model comparison, separate calibration, exact additive stress-model decomposition, marginal weather-support flags and paired year-block RMSE intervals. The stress basis combines established operations: regional climatology, standardized anomalies, upper/lower hinges, optional same-month temperature-tail and precipitation-deficit products, ridge penalties and second-difference seasonal smoothing. No individual operation is claimed as newly invented. General tools such as mgcv, glmnet, dlnm and modelling-workflow packages can implement related analyses; YieldLag's proposed value is their crop-panel-specific coordination and auditable outputs. This claim requires external-user evaluation and an explicit software comparison, rather than an assertion that existing packages cannot perform these tasks."),
("2. Data and experimental design", "The Polish inputs contain monthly weather for 1990-2019 and provincial yields for 1999-2019 across 16 voivodeships. The German external archive (Conradt, 2021; DOI 10.5281/zenodo.4468691) contains district-level monthly weather and annual yields. German regions are eligible when at least five finite initial-period yields and matching weather are available; all eligible regions are included. Yield units are dt/ha. Primary experiments use 12 monthly maximum-temperature and precipitation values each. Polish wheat and barley end their agricultural seasons in July and June, respectively; German winter wheat and winter barley use those same endpoints as declared modelling assumptions. Crop definitions differ, so cases are analyzed separately and no pooled country-transfer result is claimed."),
("2.1. Temporal separation", "Initial history is 1999-2004, tuning 2005-2008, interval calibration 2009-2011 and evaluation 2012-2018. Every origin fits coefficients and preprocessing using years strictly earlier than the predicted year. Hyperparameters remain fixed after tuning. Earlier evaluation responses may enter later-origin fits, as in sequential retrospective hindcasting. The year 2019 is excluded from primary fitting/selection and scored separately with the previously selected settings. It already existed in the source archives and is not newly collected confirmatory data. The Polish benchmark informed development; prior team exposure to the German archive is unconfirmed. Full harvest-year weather is supplied, so results do not establish operational early-season forecast skill."),
("2.2. Models and seasonal basis", "Comparators are regional trend, persistence, panel ridge, local ridge, principal-component regression, hierarchical partial pooling, stress-lag and a regularized simplex ensemble. For weather variable v and seasonal month m, the stress model estimates a training-region mean and a pooled within-region standard deviation. The standardized anomaly z enters linearly, with upper hinge max(z-tau,0), lower hinge max(-z-tau,0), and an optional product of upper temperature and lower precipitation hinges. Expanded predictors are centered/scaled using training data. Ridge and second-difference penalties control size and seasonal roughness; regional intercept/trend deviations and residual AR correction may be included. The primary threshold is tau=0.75 standardized units, not a physiological damage threshold. Coefficients are unconstrained in sign. Monthly inputs cannot reconstruct daily heat exposure or phenological timing."),
("2.3. Selection and external comparators", "Panel/local ridge and stress models each use 12 lambda/smoothing candidates. Hierarchical fitting uses 12 global-penalty, regional/global-ratio and smoothing combinations; PCR uses five component counts. The external mgcv GAM includes six smooths of temperature/precipitation means in three four-month seasonal windows, region intercepts and region trends, with three gamma candidates. Germany uses the bam discrete fREML solver with the same formula; Poland uses gam REML. The random forest uses 500 ranger trees with nine mtry/node-size combinations and seed 2718. Gaussian fits are primary; robust fitting is a Polish sensitivity. External GAM/forest fits have no residual AR correction; package AR-off results are therefore also reported. Unequal candidate counts and feature representations mean that the comparison follows a common temporal protocol, rather than equal computational cost. Ensemble base hyperparameters and stacking shrinkage reuse tuning data; meta-selection is not fully nested, although calibration/evaluation are excluded."),
("2.4. Ablations, sensitivities and spatial tests", "Separately tuned stress ablations include linear anomalies, added asymmetric tails, added compound interaction, no seasonal smoothing and no regional deviations. Prespecified sensitivities consider thresholds 0.5, 1 and 1.5, robust fitting, full seven-variable Polish inputs and six-month seasons. No-AR results condition on the original tuning-selected parameters and are not retuned. Four deterministic Polish region folds remove complete held regions from both tuning and every training origin. Only methods supporting unseen-region prediction are included, with a pooled time-trend baseline. This is a test of zero local yield history, distinct from prediction in previously observed regions."),
("2.5. Metrics and uncertainty", "Report RMSE, MAE, bias, predictive R2, trend-relative squared-error skill and within-region-centered descriptive R2. The latter removes evaluation-period regional means from the denominator and is a descriptive diagnostic, not an independently fitted detrending procedure. Paired RMSE differences use 2000 circular year-block bootstrap resamples, block length two, 95% percentile limits and seed 2718, retaining all regions within each sampled year. Block lengths one and three provide sensitivities. Only seven annual blocks underlie primary comparisons. Nominal 80% empirical bands use the type-8 quantile of separate calibration absolute errors. Compare coverage, width and interval score against tuning-error calibration on identical prediction means. Three calibration years and temporal/spatial dependence provide no distribution-free coverage guarantee."),
("2.6. Upstream ABSOLUT comparison", "A supplementary 2016-2018 Polish comparison runs upstream ABSOLUT v1.2, retaining its documented minimum of 17 yield years, nbest=23 and maximum 42 preselected features. Principal variables are temperature and precipitation; bestof is declared as 10. Each origin truncates all response inputs before that year. Portable changes replace MPI with sequential foreach, omit shell cleanup/printf in fresh isolated folders, preserve single-column data frames and compute only the requested forecast-origin target. The upstream fitting and selection operations are retained. Original GPL code is downloaded and run separately from the MIT R package, with checksums and adapter manifests. The shorter native comparison cannot support the same seven-year inference as the primary experiment."),
("3. Results", "Table 1 reports the primary common-input comparison; Figure 1 includes all primary estimators. These experiments have different inputs, fitting assumptions and tuning/calibration periods from the previously published v0.2.0 Polish reference explorer and must not be mixed with its performance numbers. Table 2 and Figure 3 show paired uncertainty relative to partial pooling. Performance should be interpreted case by case: a lower point RMSE is not evidence of a universal improvement, particularly when its interval includes zero. The separately tuned ablations in Figure 2 identify where additional terms help or hurt; they cannot by themselves establish a causal response to heat or water deficit."),
("3.1. Calibration, spatial support and sensitivity", "Separate calibration removes direct reuse of model-selection errors, but it does not necessarily improve observed coverage. Figure 4 reports both calibration procedures, including undercoverage. Coverage must be interpreted together with interval width and score. Figure 5 shows weak prediction in entirely withheld Polish provinces: local yield levels/history contribute materially to performance in known regions. Full-weather, shortened-season, robustness, threshold and AR-off sensitivity tables accompany the analysis. Large threshold sensitivity argues against interpreting a chosen anomaly hinge as a measured crop damage threshold. The supplementary native comparison in Figure 6 uses only 48 province-year observations per crop; uncertainty from three annual blocks is necessarily weak."),
("4. Discussion", "The evidence supports YieldLag as a transparent framework for comparative regional statistical modelling. It does not establish a universally superior stress estimator, a mechanistic crop model or reliable prediction without local yield history. Negative results and instability are useful guidance for users: nonlinear terms should earn their complexity against partial pooling and external additive baselines. Exact decomposition verifies the fitted equation, but components are centered statistical associations rather than causal losses; correlated climate variables and regularization further limit coefficient interpretation. Marginal training-range flags do not certify multivariate support or calibrated confidence."),
("4.1. Limitations and next validation", "The study combines two countries but not harmonized identical crop definitions, and German district scale differs from Polish provincial scale. The public external archive is an additional benchmark, not an assured untouched country test. A future confirmatory study should freeze methods before obtaining genuinely uninspected later observations, harmonize crop definitions and spatial support, and use forecasts available at the stated issue date. Polish fixed-area weights and source solar derivation remain incompletely documented; therefore primary comparative inference uses region-year errors and the two weather variables with clearer working conventions. National weighted references are not independent observations. External adoption and independent human reproduction remain necessary to assess practical software reuse."),
("5. Availability and reproducibility", "Software: https://github.com/MR-Eini/yieldlag, version 0.3.0, MIT code. Website: https://mr-eini.github.io/yieldlag/. Scripts, temporal protocol, candidate grids, selected parameters, row-level predictions, session information, paired bootstrap tables, native adapter manifests and downloadable figures accompany this draft. The original v0.2.0 source is frozen by commit/hash. German downloads are checksum verified and retain CC-BY-4.0 archive metadata plus the agricultural tables' Data licence Germany attribution terms. Poland derivatives retain the provider/source processing notice separately from the code license. A Zenodo record and DOI require authenticated archival completion; this draft does not claim one has been issued."),
("Author and AI-use declarations", "Mohammad Reza Eini is the current software maintainer and proposed manuscript author. Final contributors, affiliations, funding and conflict declarations require author confirmation. OpenAI Codex assisted with code development, tests, analysis scripts, documentation, plots and manuscript drafting. Exact deployed model/version and the scope of human review must be confirmed before submission. Automated tests and recomputation are documented; they do not substitute for author scientific review or an independent researcher's reproduction. No completed human review, external adoption or journal submission is asserted in this draft."),
("References", "Conradt, T. (2022). Choosing multiple linear regressions for weather-based crop yield prediction with ABSOLUT v1.2 applied to the districts of Germany. International Journal of Biometeorology, 66, 2287-2300. https://doi.org/10.1007/s00484-022-02356-5\n\nConradt, T. (2021). German ABSOLUT input archive. https://doi.org/10.5281/zenodo.4468691. ABSOLUT v1.2 software: https://doi.org/10.5281/zenodo.5789350.\n\nEini, M. R., Conradt, T., and Piniewski, M. (2026). Sequential hybridization enhances the reliability of a statistical crop yield model - exemplified by wheat and sugar beet yields in the provinces of Poland. Theoretical and Applied Climatology. https://doi.org/10.1007/s00704-026-06322-8\n\nSchlenker, W., and Roberts, M. J. (2009). Nonlinear temperature effects indicate severe damages to U.S. crop yields under climate change. PNAS. https://doi.org/10.1073/pnas.0906865106\n\nGasparrini, A., Armstrong, B., and Kenward, M. G. (2010). Distributed lag non-linear models. Statistics in Medicine. https://doi.org/10.1002/sim.3940\n\nWood, S. N. (2011). Fast stable restricted maximum likelihood and marginal likelihood estimation of semiparametric generalized linear models. JRSS B. https://doi.org/10.1111/j.1467-9868.2010.00749.x\n\nWright, M. N., and Ziegler, A. (2017). ranger: A fast implementation of random forests for high dimensional data in C++ and R. Journal of Statistical Software. https://doi.org/10.18637/jss.v077.i01")]
title="YieldLag: a reproducible framework for regional climate-yield modelling with seasonal nonlinear responses and chronological evaluation"
intro="Research manuscript draft | YieldLag 0.3.0 | 2 October 2026\n\nMohammad Reza Eini | mohammad_eini@sggw.edu.pl"
md="# "+title+"\n\n"+intro+"\n\n"
for heading,text in sections:
    if heading=="3. Results":text=results_text+" "+text
    md+="## "+heading+"\n\n"+text+"\n\n"
    if heading=="3. Results":
        md+="Table 1. Primary evaluation RMSE (dt/ha), 2012-2018.\n\n"+md_table(primary_table)+"\n\n"
        md+="Table 2. Paired stress-lag minus partial-pooling RMSE differences.\n\n"+md_table(uncertainty_table)+"\n\n"
captions={"model_comparison":"Figure 1. All primary model RMSEs under the common chronological protocol. Cases differ in crop definition and spatial scale.",
 "stress_ablations":"Figure 2. Separately tuned seasonal-basis ablations on identical test observations. Extra complexity may increase error.",
 "paired_uncertainty":"Figure 3. Paired RMSE differences and 95% circular year-block bootstrap intervals relative to partial pooling. Seven annual blocks limit inference.",
 "interval_calibration":"Figure 4. Nominal 80% interval coverage versus width. Separate calibration excludes model-selection errors but does not guarantee coverage.",
 "spatial_holdouts":"Figure 5. Complete-region holdouts in Poland. All held-region responses are excluded from tuning and training.",
 "absolut_comparison":"Figure 6. Upstream ABSOLUT comparison with chronological response truncation, 2016-2018. Only three annual blocks contribute."}
md+="## Figures\n\n"
for name,caption in captions.items():md+=f"![{caption}](figures/{name}.png)\n\n{caption}\n\n"
(MANUSCRIPT/"yieldlag_manuscript.md").write_text(md,encoding="utf-8")

font=Path(matplotlib.get_data_path())/"fonts/ttf"
for name,file in [("Body","DejaVuSerif.ttf"),("BodyBold","DejaVuSerif-Bold.ttf"),("Label","DejaVuSans.ttf")]:
    pdfmetrics.registerFont(TTFont(name,str(font/file)))
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name="Text",fontName="Body",fontSize=10,leading=15,spaceAfter=9))
styles.add(ParagraphStyle(name="Section",fontName="BodyBold",fontSize=13,leading=18,spaceBefore=12,spaceAfter=8,keepWithNext=True))
styles.add(ParagraphStyle(name="PaperTitle",fontName="BodyBold",fontSize=19,leading=25,spaceAfter=16))
styles.add(ParagraphStyle(name="Caption",fontName="Label",fontSize=9,leading=13,spaceAfter=12))
story=[Paragraph(html.escape(title),styles["PaperTitle"]),Paragraph(intro.replace("\n","<br/>"),styles["Caption"])]
def table(frame):
    data=[[Paragraph(html.escape(str(v)),styles["Caption"]) for v in frame.columns]]
    data+=[[Paragraph(html.escape(str(v)),styles["Caption"]) for v in row] for row in frame.itertuples(index=False,name=None)]
    widths=([130,48,35,54,63,57,48,45] if len(frame.columns)==8 else [200,90,180])
    t=Table(data,colWidths=widths,repeatRows=1,hAlign="LEFT")
    t.setStyle(TableStyle([("VALIGN",(0,0),(-1,-1),"TOP"),("BACKGROUND",(0,0),(-1,0),colors.HexColor("#e9f1ed")),
      ("LINEBELOW",(0,0),(-1,0),.7,colors.HexColor("#21624d")),("BOTTOMPADDING",(0,0),(-1,-1),5)]))
    return t
for heading,text in sections:
    if heading=="3. Results":text=results_text+" "+text
    story.append(Paragraph(html.escape(heading),styles["Section"]))
    for para in text.split("\n\n"):story.append(Paragraph(html.escape(para),styles["Text"]))
    if heading=="3. Results":
        story+=[KeepTogether([Paragraph("Table 1. Primary RMSE (dt/ha), 2012-2018.",styles["Caption"]),table(primary_table)]),Spacer(1,12),
          KeepTogether([Paragraph("Table 2. Stress-lag minus partial-pooling RMSE differences and 95% intervals.",styles["Caption"]),table(uncertainty_table)])]
for name,caption in captions.items():
    story.append(PageBreak())
    image=Image(str(FIGURES/f"{name}.png"))
    scale=min(480/image.imageWidth,590/image.imageHeight)
    image.drawWidth=image.imageWidth*scale;image.drawHeight=image.imageHeight*scale
    story+=[image,Spacer(1,12),Paragraph(html.escape(caption),styles["Caption"])]
def footer(canvas,doc):
    canvas.setFont("Label",8);canvas.setFillColor(colors.HexColor("#60736b"))
    canvas.drawString(45,27,"YieldLag | Research manuscript draft | 2 October 2026")
    canvas.drawRightString(550,27,str(doc.page))
SimpleDocTemplate(str(MANUSCRIPT/"yieldlag_manuscript.pdf"),pagesize=(595.28,841.89),
 leftMargin=45,rightMargin=45,topMargin=45,bottomMargin=45,title=title,author="Mohammad Reza Eini").build(story,onFirstPage=footer,onLaterPages=footer)

# Export the complete evidence tables, figures and manuscript, excluding model caches/raw provider inputs.
site=ROOT/"site"
download=site/"downloads/research"
download.mkdir(parents=True,exist_ok=True)
for case in CASES:
    target=download/case;target.mkdir(exist_ok=True)
    for f in (RESULTS/case).glob("*.csv"):shutil.copyfile(f,target/f.name)
    for f in (RESULTS/case).glob("absolut_manifest*.json"):shutil.copyfile(f,target/f.name)
for f in RESULTS.glob("*.csv"):shutil.copyfile(f,download/f.name)
for f in [ROOT/"research/protocol.md",ROOT/"research/frozen_v020.json",MANUSCRIPT/"yieldlag_manuscript.pdf",MANUSCRIPT/"yieldlag_manuscript.md"]:
    shutil.copyfile(f,download/f.name)
with zipfile.ZipFile(download/"yieldlag_manuscript_bundle.zip","w",zipfile.ZIP_DEFLATED) as archive:
    for f in sorted(MANUSCRIPT.rglob("*")):
        if f.is_file() and "qa" not in f.relative_to(MANUSCRIPT).parts:
            archive.write(f,f.relative_to(MANUSCRIPT).as_posix())
figdownload=download/"figures";figdownload.mkdir(exist_ok=True)
for f in FIGURES.iterdir():shutil.copyfile(f,figdownload/f.name)
plotdir=site/"assets/plots/research";plotdir.mkdir(parents=True,exist_ok=True)
for f in FIGURES.iterdir():shutil.copyfile(f,plotdir/f.name)
checksums=[f"{hashlib.sha256(f.read_bytes()).hexdigest()}  {f.relative_to(download).as_posix()}" for f in sorted(download.rglob("*")) if f.is_file() and f.name!="SHA256SUMS.txt"]
(download/"SHA256SUMS.txt").write_text("\n".join(checksums)+"\n",encoding="utf-8")
import sys
sys.path.insert(0,str(ROOT/"analysis"))
from build_website import shell,hero,layout,md as render_md
body=hero("Comparative evaluation","Where does seasonal complexity help?",
 "A common chronological study across Poland and Germany, with external baselines, separate calibration and complete-region tests.")
prose="<h2 id='design'>Study design</h2><p>Initial history: 1999-2004. Tuning: 2005-2008. Calibration: 2009-2011. Evaluation: 2012-2018. Primary models use 24 monthly maximum-temperature and precipitation terms. German winter crops and Polish aggregate crops are analyzed separately.</p><p>These are retrospective benchmarks using complete seasonal weather. The external German archive is additional evaluation data; prior team exposure is unconfirmed. Results establish neither causal effects nor operational early-forecast skill.</p>"
prose+="<h2 id='performance'>Performance</h2><p>Evaluation RMSE in dt/ha (1 dt/ha = 0.1 t/ha), 2012–2018. N counts region-year observations.</p><div class='table-wrap'>"+render_md(md_table(primary_table))+"</div><p>The stress model improves the point estimate over partial pooling only for Polish wheat. Every paired uncertainty interval includes zero.</p>"
prose+="<h2 id='uncertainty'>Paired uncertainty</h2><div class='table-wrap'>"+render_md(md_table(uncertainty_table))+"</div><p>Differences in dt/ha below zero favor stress lag. Intervals resample complete year blocks; seven annual blocks limit inference.</p>"
prose+="<h2 id='figures'>Figures</h2>"
for name,caption in captions.items():
    prose+=f"<figure><a href='assets/plots/research/{name}.png'><img loading='lazy' src='assets/plots/research/{name}.png' alt='{html.escape(caption)}'></a><figcaption>{html.escape(caption)}</figcaption><p><a href='assets/plots/research/{name}.svg' download>Download SVG</a></p></figure>"
prose+="<h2 id='downloads'>Reproduce and inspect</h2><p><a href='downloads/research/yieldlag_manuscript.pdf'>Manuscript draft (PDF)</a> · <a href='downloads/research/yieldlag_manuscript_bundle.zip'>Editable manuscript and figures (ZIP)</a> · <a href='downloads/research/protocol.md'>Experimental protocol</a> · <a href='downloads/research/combined_metrics.csv'>All model metrics</a> · <a href='downloads/research/SHA256SUMS.txt'>Checksums</a></p><p>The GitHub repository includes the study scripts and checksum-verified external-data downloader. The manuscript reports all limitations, including weak unseen-region performance and incomplete Polish solar/area metadata.</p>"
for case in CASES:
    prose+=f"<h3>{LABELS[case]}</h3><ul>"
    for f in sorted((download/case).glob("*.csv")):
        prose+=f"<li><a href='downloads/research/{case}/{f.name}' download>{f.stem.replace('_',' ')}</a></li>"
    prose+="</ul>"
body+=layout(prose,[("design","Design"),("performance","Performance"),("uncertainty","Uncertainty"),("figures","Figures"),("downloads","Downloads")])
(site/"research.html").write_text(shell("Comparative evaluation",body,"Research"),encoding="utf-8")
manifest={"cases":CASES,"metrics_recomputed":int(len(summary)),"figures":len(captions),
 "year_leakage_checks":"all TrainEnd < Year", "package_version":"0.3.0"}
(RESULTS/"evidence_verification.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
print(json.dumps(manifest))
