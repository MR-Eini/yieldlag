"""Recompute research metrics and verify chronology/downloads using the stdlib."""
from pathlib import Path
import csv
import hashlib
import math

ROOT = Path(__file__).resolve().parents[1]
CASES = ['poland_wheat', 'poland_barley', 'germany_wheat', 'germany_barley']

def read(path):
    with path.open(encoding='utf-8', newline='') as stream:
        return list(csv.DictReader(stream))

def close(actual, expected):
    assert math.isclose(actual, float(expected), rel_tol=1e-9, abs_tol=1e-9), (actual, expected)

def verify():
    combined = read(ROOT / 'research/results/combined_metrics.csv')
    count = 0
    for case in CASES:
        folder = ROOT / 'research/results' / case
        rows = read(folder / 'evaluation_predictions.csv')
        assert len({(r['Method'], r['RS'], r['Year']) for r in rows}) == len(rows)
        assert {int(r['Year']) for r in rows} == set(range(2012, 2019))
        assert all(int(r['TrainEnd']) < int(r['Year']) for r in rows)
        reference = {(r['RS'], r['Year']): r for r in rows if r['Method'] == 'trend'}
        for metric in (r for r in combined if r['Case'] == case):
            part = [r for r in rows if r['Method'] == metric['Method']]
            assert {(r['RS'], r['Year']) for r in part} == set(reference)
            observed = [float(r['Observed']) for r in part]
            error = [float(r['Predicted']) - float(r['Observed']) for r in part]
            square = sum(e * e for e in error)
            mean = sum(observed) / len(part)
            trend_square = sum((float(reference[(r['RS'], r['Year'])]['Predicted']) - float(r['Observed'])) ** 2 for r in part)
            assert all(float(reference[(r['RS'], r['Year'])]['Observed']) == float(r['Observed']) for r in part)
            region_means = {}
            for region in {r['RS'] for r in part}:
                values = [float(r['Observed']) for r in part if r['RS'] == region]
                region_means[region] = sum(values) / len(values)
            close(math.sqrt(square / len(part)), metric['RMSE'])
            close(sum(abs(e) for e in error) / len(part), metric['MAE'])
            close(sum(error) / len(part), metric['Bias'])
            close(1 - square / sum((o - mean) ** 2 for o in observed), metric['R2'])
            close(1 - square / trend_square, metric['TrendRelativeSkill'])
            close(1 - square / sum((float(r['Observed']) - region_means[r['RS']]) ** 2 for r in part), metric['WithinRegionR2'])
            close(sum(float(r['Lower80']) <= float(r['Observed']) <= float(r['Upper80']) for r in part) / len(part), metric['Coverage80'])
            close(sum(float(r['Upper80']) - float(r['Lower80']) for r in part) / len(part), metric['MeanWidth80'])
            assert int(metric['N']) == len(part)
            count += 1
        for path in folder.glob('*predictions*.csv'):
            for row in read(path):
                if 'TrainEnd' in row:
                    assert int(row['TrainEnd']) < int(row['Year']), (path, row)
        site_folder = ROOT / 'site/downloads/research' / case
        for path in folder.glob('*.csv'):
            assert path.read_bytes() == (site_folder / path.name).read_bytes(), path
    downloads = ROOT / 'site/downloads/research'
    for line in (downloads / 'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
        digest, name = line.split('  ', 1)
        path = (downloads / name).resolve()
        assert path.is_relative_to(downloads.resolve())
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, name
    print(f'PASS: {count} research metric rows independently recomputed; paired rows, chronological origins, website exports and SHA256 checksums verified.')

if __name__ == '__main__':
    verify()
