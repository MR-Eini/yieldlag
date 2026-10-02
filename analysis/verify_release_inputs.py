"""Verify release data bytes using the Python standard library (no packages)."""
from pathlib import Path
import csv
import hashlib

root = Path(__file__).resolve().parents[1] / "inst" / "extdata" / "poland"
with (root / "input_sha256.csv").open(encoding="utf-8", newline="") as stream:
    records = list(csv.DictReader(stream))
for record in records:
    path = root / record["File"]
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != record["SHA256"]:
        raise SystemExit(f"Input checksum mismatch: {record['File']}")
with (root / "weather_preparation.csv").open(encoding="utf-8", newline="") as stream:
    for record in csv.DictReader(stream):
        actual = hashlib.sha256((root / "weather" / record["File"]).read_bytes()).hexdigest()
        if actual != record["ReleaseSHA256"]:
            raise SystemExit(f"Weather preparation checksum mismatch: {record['File']}")
print(f"Verified {len(records)} bundled input SHA-256 checksums and weather preparation hashes.")
