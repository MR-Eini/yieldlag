"""Run upstream GPL ABSOLUT v1.2 at chronological origins without MPI.

Download original code separately; never incorporate GPL implementation into
the MIT R package. Only evaluate the forecast-origin column, which is the same
column that a full retrospective run would calculate with all response inputs
truncated before that origin. Preserve the upstream 42-feature cap and nbest=23.
"""
from pathlib import Path
import hashlib, json, re, subprocess, sys, urllib.request, csv, shutil

ROOT = Path(__file__).resolve().parent.parent
RSCRIPT = Path(r"C:\Program Files\R\R-4.5.2\bin\Rscript.exe")
if not RSCRIPT.exists():
    RSCRIPT = Path(shutil.which("Rscript") or "Rscript")
SOURCE = ROOT / "research/external/absolut"
SOURCE.mkdir(parents=True, exist_ok=True)
metadata = json.load(urllib.request.urlopen("https://zenodo.org/api/records/5789350"))
(SOURCE / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
for entry in metadata["files"]:
    if not entry["key"].endswith(".R"):
        continue
    path = SOURCE / entry["key"]
    if not path.exists():
        path.write_bytes(urllib.request.urlopen(entry["links"]["self"]).read())
    if "md5:" + hashlib.md5(path.read_bytes()).hexdigest() != entry["checksum"]:
        raise ValueError("Upstream source checksum mismatch")

case = sys.argv[1] if len(sys.argv) > 1 else "poland_wheat"
if not case.startswith("poland_"):
    raise SystemExit("This adapter currently evaluates the Poland provincial inputs.")
crop = case.removeprefix("poland_")
harvest = 7 if crop == "wheat" else 6
source_data = ROOT / "inst/extdata/poland"
yield_rows = list(csv.DictReader((source_data / "yield.csv").open(encoding="utf-8-sig")))
year_col = next(iter(yield_rows[0]))
upstream_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCE.glob("*.R")}
summary = []
for origin in (2016, 2017, 2018):
    directory = ROOT / f"research/external/absolut-runs/{case}-{origin}"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "DistrictWeather").mkdir(exist_ok=True)
    (directory / "DistrictFeatures").mkdir(exist_ok=True)
    for weather in (source_data / "weather").glob("pl_*.dat"):
        rs = int(weather.stem.split("_")[1])
        shutil.copyfile(weather, directory / f"DistrictWeather/dw_{rs:05d}.dat")
    with (directory / "yield-indat.csv").open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Year", "RS", "Region", crop])
        for row in yield_rows:
            if int(row[year_col]) < origin:
                writer.writerow([row[year_col], row["RS"], row.get("Region", row["RS"]), row[crop]])
    controls = f"./DistrictWeather ./DistrictFeatures\nMAX PCP\n{crop}\n{origin} {origin-1}\n{harvest}\n17\n10\n"
    (directory / "absolutcontrol.dat").write_text(controls, encoding="utf-8")
    manifest = {"case": case, "origin": origin, "response_cutoff": origin-1,
        "upstream_doi": "10.5281/zenodo.5789350", "source_sha256": upstream_hashes,
        "modifications": ["sequential foreach backend instead of MPI",
            "omit platform shell cleanup/printf commands in a fresh isolated directory",
            "compute only the forecast-origin target column",
            "preserve data frames for a single target column", "upstream default 42-feature cap retained"],
        "minimum_history": 17, "principal_variables": ["MAX", "PCP"],
        "bestof": 10, "status": "running"}
    manifest_path = directory / "adapter_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    for number in (112, 212, 312, 412):
        text = (SOURCE / f"{number}_absolut.R").read_text(encoding="utf-8-sig")
        text = text.replace('library("doMPI")', 'library("foreach"); registerDoSEQ()')
        text = re.sub(r"(?m)^\s*(cl <- startMPIcluster\(\)|registerDoMPI\(cl\)|closeCluster\(cl\)|mpi.quit\(\))\s*$", "", text)
        text = re.sub(r"(?m)^\s*system\(.*$", "", text)
        text = text.replace("%dopar%", "%do%")
        if number == 112:
            text = text.replace("foreach(j=1:nrow(motab)", "foreach(j=which(motab$year==lastweatheryear)")
            text = text.replace("canditab <- canditab[1:maxcutoff,]", "canditab <- canditab[1:maxcutoff,,drop=FALSE]")
        elif number == 212:
            text = text.replace("for (target in overallyears)", "for (target in max(overallyears))")
        elif number == 412:
            text = text.replace("for (year in overallyears)", "for (year in max(overallyears))")
        text = text.replace("presel <- presel[1:min(nrow(presel),42),]",
                            "presel <- presel[1:min(nrow(presel),42),,drop=FALSE]")
        patch = directory / f"{number}_portable.R"
        patch.write_text(text, encoding="utf-8")
        print(case, origin, number, flush=True)
        with (directory / f"stage-{number}.log").open("w", encoding="utf-8") as log:
            try:
                completed = subprocess.run([str(RSCRIPT), str(patch)], cwd=directory,
                    stdout=log, stderr=subprocess.STDOUT, timeout=900)
            except subprocess.TimeoutExpired:
                manifest["status"] = "stage_timeout"
                manifest["failed_stage"] = number
                manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
                raise
        if completed.returncode:
            manifest["status"] = "stage_failed"
            manifest["failed_stage"] = number
            manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            raise RuntimeError(f"ABSOLUT {number} failed; inspect {directory / f'stage-{number}.log'}")
    manifest["status"] = "complete"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    summary.append({"case": case, "origin": origin, "output": (directory / "absolut-412-output.dat").relative_to(ROOT).as_posix()})
(ROOT / f"research/results/{case}/absolut_runs.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
