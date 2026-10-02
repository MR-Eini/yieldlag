"""Download and checksum the pinned German benchmark and extract safely."""
from pathlib import Path
import hashlib, json, urllib.request, zipfile
ROOT = Path(__file__).resolve().parent
raw = ROOT / "external/raw"
raw.mkdir(parents=True, exist_ok=True)
metadata = json.load(urllib.request.urlopen("https://zenodo.org/api/records/4468691"))
(raw / "zenodo-4468691.json").write_text(json.dumps(metadata,indent=2),encoding="utf-8")
manifest = []
for entry in metadata["files"]:
    target = raw / entry["key"]
    if target.parent.resolve() != raw.resolve():
        raise ValueError("Unexpected archive filename")
    target.write_bytes(urllib.request.urlopen(entry["links"]["self"]).read())
    if "md5:"+hashlib.md5(target.read_bytes()).hexdigest() != entry["checksum"]:
        raise ValueError("Source checksum mismatch")
    manifest.append({"file":target.name,"sha256":hashlib.sha256(target.read_bytes()).hexdigest(),
        "source_checksum":entry["checksum"],"url":entry["links"]["self"]})
destination = (raw/"weather").resolve()
with zipfile.ZipFile(raw/"districtweather.zip") as archive:
    for member in archive.infolist():
        resolved = (destination/member.filename).resolve()
        if not resolved.is_relative_to(destination):
            raise ValueError("Archive member escapes extraction directory")
    archive.extractall(destination)
(ROOT/"external/download_manifest.json").write_text(json.dumps(manifest,indent=2),encoding="utf-8")
print("Verified German data from DOI 10.5281/zenodo.4468691")
