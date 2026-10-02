"""Check local links and recompute published evaluation metrics (stdlib only)."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import csv
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"

class Links(HTMLParser):
    def __init__(self):
        super().__init__(); self.links=[]; self.ids=set()
    def handle_starttag(self, tag, attributes):
        attrs=dict(attributes)
        if attrs.get('id'): self.ids.add(attrs['id'])
        for key in ['href','src']:
            if attrs.get(key): self.links.append(attrs[key])

def close(actual, expected):
    assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), (actual, expected)

def verify():
    parsed={}
    for p in SITE.rglob('*.html'):
        parser=Links(); parser.feed(p.read_text(encoding='utf-8')); parsed[p]=parser
    count=0
    for path, page in parsed.items():
        for href in page.links:
            target=urlsplit(href)
            if target.scheme or target.netloc: continue
            destination=(path.parent / unquote(target.path)).resolve() if target.path else path
            if destination.is_dir(): destination=destination/'index.html'
            assert destination.is_relative_to(SITE), (path,href)
            assert destination.exists(), (path.relative_to(SITE),href)
            if target.fragment and destination.suffix=='.html':
                assert unquote(target.fragment) in parsed[destination].ids, (path.relative_to(SITE),href,'missing anchor')
            count+=1
    data=json.loads((SITE/'assets/data/poland.json').read_text(encoding='utf-8'))
    for crop, run in data.items():
        assert len(run['region_names'])==16
        assert run['metadata']['training_yield_count']==320
        assert run['metadata']['weather_terms']==84
        tuning=run['method_selection_tuning']
        assert min(tuning,key=lambda row:row['RMSE'])['Method']==run['metadata']['selected_method']
        for metric in run['model_metrics']:
            method=metric['Method'];national=metric['Level']=='National'
            rows=[r for r in run['national_cv_predictions' if national else 'province_cv_predictions'] if r['Method']==method and r['Phase']=='evaluation']
            assert len(rows)==(7 if national else 112)
            assert {r['Year'] for r in rows}==set(range(2012,2019))
            observed=[r['ObservedWeighted' if national else 'Observed'] for r in rows]
            predicted=[r['PredictedWeighted' if national else 'Predicted'] for r in rows]
            lower=[r['Lower80Weighted' if national else 'Lower80'] for r in rows]
            upper=[r['Upper80Weighted' if national else 'Upper80'] for r in rows]
            errors=[p-o for o,p in zip(observed,predicted)]
            mean=sum(observed)/len(rows)
            close(math.sqrt(sum(e*e for e in errors)/len(rows)),metric['RMSE'])
            close(sum(abs(e) for e in errors)/len(rows),metric['MAE'])
            close(sum(errors)/len(rows),metric['Bias'])
            close(1-sum(e*e for e in errors)/sum((o-mean)**2 for o in observed),metric['R2'])
            close(sum(l<=o<=u for o,l,u in zip(observed,lower,upper))/len(rows),metric['Coverage80'])
            close(sum(u-l for l,u in zip(lower,upper))/len(rows),metric['MeanWidth80'])
        for r in run['stress_components_2019']:
            close(sum(r[k] for k in ['Intercept','Trend','Regional','LinearAnomaly','UpperTail','LowerTail','HotDry','ARCorrection']),r['Prediction'])
            matched=next(p for p in run['province_predictions'] if p['Method']=='stress_lag' and str(p['RS'])==str(r['RS']) and p['Year']==2019)
            close(matched['Predicted'],r['Prediction'])
        for metric in run['model_metrics']:
            path=SITE/'downloads'/crop/'model_metrics.csv'
            with path.open(encoding='utf-8',newline='') as stream:
                exported=next(r for r in csv.DictReader(stream) if r['Method']==metric['Method'] and r['Level']==metric['Level'])
            close(float(exported['RMSE']),metric['RMSE'])
        folder=SITE/'downloads'/crop
        for line in (folder/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines():
            digest,name=line.split('  ',1)
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest, name
    print(f'PASS: {len(parsed)} HTML pages, {count} local references, 32 metric rows independently recomputed, 32 exact prediction decompositions, and download checksums.')

if __name__=='__main__': verify()
