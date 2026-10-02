/* The explorer renders saved model outputs; it performs no model fitting. */
const labels = {trend:'Trend',persistence:'Persistence',panel_ridge:'Panel ridge',
  local_ridge:'Local ridge',pcr:'PCR',hierarchical:'Hierarchical',stress_lag:'Stress lag',ensemble:'Ensemble'};
const escapeHTML = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const format = (value, digits=3) => Number.isFinite(value) ? value.toFixed(digits) : '—';
let runs, crop = 'barley';
const element = id => document.getElementById(id);
const row = (cells, selected=false) => `<tr${selected?' class="selected"':''}>${cells.map((v,i)=>`<td${i?' class="numeric"':''}>${v}</td>`).join('')}</tr>`;
const table = (head, body) => `<table><thead><tr>${head.map(h=>`<th scope="col">${h}</th>`).join('')}</tr></thead><tbody>${body.join('')}</tbody></table>`;

function metrics() {
  const selected = runs[crop].metadata.selected_method;
  const rows = runs[crop].model_metrics.filter(r=>r.Level===element('metric-level').value).sort((a,b)=>a.RMSE-b.RMSE);
  element('metrics-table').innerHTML = table(['Method','RMSE','MAE','Bias','R²','80% coverage','Band width'], rows.map(r=>row([
    escapeHTML(labels[r.Method])+(r.Method===selected?' <span class="badge">tuning-selected</span>':''),
    format(r.RMSE),format(r.MAE),format(r.Bias),format(r.R2),format(r.Coverage80*100,1)+'%',format(r.MeanWidth80)
  ],r.Method===selected)));
}

function predictions() {
  const run=runs[crop], method=element('chart-method').value, region=element('chart-region').value;
  const national=region==='national';
  const select = records=>records.filter(r=>r.Method===method && (national || String(r.RS)===region));
  const cv=select(national?run.national_cv_predictions:run.province_cv_predictions);
  const last=select(national?run.national_predictions:run.province_predictions).filter(r=>r.Year===2019);
  const series=[...cv,...last].sort((a,b)=>a.Year-b.Year).map(r=>({
    year:r.Year,phase:r.Year===2019?'future':r.Phase,
    observed:national?r.ObservedWeighted:r.Observed,
    predicted:national?r.PredictedWeighted:r.Predicted,
    lower:national?r.Lower80Weighted:r.Lower80,upper:national?r.Upper80Weighted:r.Upper80
  }));
  const title=`${crop[0].toUpperCase()+crop.slice(1)} · ${labels[method]} · ${national?'Area-weighted national':run.region_names[region]}`;
  element('chart-title').textContent=title;
  const width=1040,height=430,left=68,right=25,top=24,bottom=65;
  const values=series.flatMap(r=>[r.observed,r.predicted,r.lower,r.upper]).filter(Number.isFinite);
  const lo=Math.floor((Math.min(...values)-2)/5)*5,hi=Math.ceil((Math.max(...values)+2)/5)*5;
  const x=year=>left+(year-2005.5)/(2019.5-2005.5)*(width-left-right);
  const y=value=>height-bottom-(value-lo)/(hi-lo)*(height-top-bottom);
  const path = (points,key) => points.filter(r=>Number.isFinite(r[key])).map((r,i)=>`${i?'L':'M'}${x(r.year).toFixed(2)},${y(r[key]).toFixed(2)}`).join(' ');
  const area = series.map(r=>`${x(r.year)},${y(r.upper)}`).concat([...series].reverse().map(r=>`${x(r.year)},${y(r.lower)}`)).join(' ');
  let svg=`<svg viewBox="0 0 ${width} ${height}" role="img" aria-labelledby="chart-svg-title chart-svg-desc"><title id="chart-svg-title">${escapeHTML(title)}</title><desc id="chart-svg-desc">Observed and chronological predicted yields, with empirical 80% intervals. Tuning is 2006–2011; evaluation is 2012–2018; 2019 is a separate retrospective prediction.</desc>`;
  svg+=`<rect x="${x(2005.5)}" y="${top}" width="${x(2011.5)-x(2005.5)}" height="${height-top-bottom}" fill="#fbf4df"/><rect x="${x(2011.5)}" y="${top}" width="${x(2018.5)-x(2011.5)}" height="${height-top-bottom}" fill="#f1f6f0"/>`;
  for(let i=0;i<=5;i++) {
    const value=lo+(hi-lo)*i/5;
    svg+=`<line x1="${left}" x2="${width-right}" y1="${y(value)}" y2="${y(value)}" stroke="#dfe6dd"/><text x="${left-12}" y="${y(value)+4}" text-anchor="end" font-size="12" fill="#64736a">${format(value,0)}</text>`;
  }
  for(let year=2006;year<=2019;year++) svg+=`<text x="${x(year)}" y="${height-bottom+25}" text-anchor="middle" font-size="12" fill="#64736a">${year}</text>`;
  svg+=`<polygon points="${area}" fill="#b8d3c2" opacity=".4"/><path d="${path(series,'observed')}" fill="none" stroke="#213a30" stroke-width="2.4"/><path d="${path(series.filter(r=>r.phase!=='future'),'predicted')}" fill="none" stroke="#21624d" stroke-width="2.4"/>`;
  series.forEach(r=>{
    if(Number.isFinite(r.observed)) svg+=`<circle cx="${x(r.year)}" cy="${y(r.observed)}" r="3.5" fill="#213a30"><title>${r.year} observation: ${format(r.observed)} dt/ha</title></circle>`;
    const colour=r.phase==='future'?'#b7791f':'#21624d';
    svg+=`<circle cx="${x(r.year)}" cy="${y(r.predicted)}" r="${r.phase==='future'?6:3.5}" fill="${colour}"><title>${r.year} ${r.phase} prediction: ${format(r.predicted)} dt/ha; band ${format(r.lower)}–${format(r.upper)}</title></circle>`;
  });
  svg+=`<line x1="${x(2018.5)}" x2="${x(2018.5)}" y1="${top}" y2="${height-bottom}" stroke="#899e8d" stroke-dasharray="3,4"/><text x="${(width+left-right)/2}" y="${height-8}" text-anchor="middle" font-size="13" fill="#64736a">Harvest year</text><text x="16" y="${height/2}" transform="rotate(-90 16 ${height/2})" text-anchor="middle" font-size="13" fill="#64736a">Yield (dt/ha)</text></svg>`;
  element('prediction-chart').innerHTML=svg;
  const future=run.province_predictions.filter(r=>r.Method===method&&r.Year===2019).sort((a,b)=>String(a.RS).localeCompare(String(b.RS)));
  element('forecast-table').innerHTML=table(['Province','Observed','Predicted','Error','Lower 80%','Upper 80%','Outside terms'],future.map(r=>{
    const support=run.support_2019.find(s=>s.Method===method&&String(s.RS)===String(r.RS));
    return row([escapeHTML(run.region_names[String(r.RS)]),format(r.Observed),format(r.Predicted),format(r.Predicted-r.Observed),format(r.Lower80),format(r.Upper80),`${support.OutsideTerms} / ${support.TotalTerms}`]);
  }));
}

function updateCrop(next) {
  crop=next;
  const run=runs[crop], selected=run.metadata.selected_method;
  document.querySelectorAll('[data-crop]').forEach(button=>button.setAttribute('aria-selected',String(button.dataset.crop===crop)));
  const province=run.model_metrics.filter(r=>r.Level==='Province-year');
  const selectedRow=province.find(r=>r.Method===selected),best=[...province].sort((a,b)=>a.RMSE-b.RMSE)[0];
  element('crop-summary').textContent=`${crop[0].toUpperCase()+crop.slice(1)}: ${labels[selected]} was selected by earlier tuning RMSE. Its later province-year RMSE was ${format(selectedRow.RMSE)} dt/ha. ${best.Method===selected?'The lowest later score belonged to the same method.':`The lowest later score was ${format(best.RMSE)} dt/ha for ${labels[best.Method]}; this later ranking was not used for automatic selection.`}`;
  element('chart-method').value=selected;
  element('chart-region').innerHTML='<option value="national">Area-weighted national</option>'+Object.entries(run.region_names).map(([rs,name])=>`<option value="${escapeHTML(rs)}">${escapeHTML(name)}</option>`).join('');
  document.querySelectorAll('[data-plot]').forEach(img=>{
    img.src=`assets/plots/${crop}/${img.dataset.plot}.png`;
    img.alt=img.alt.replace(/Poland (barley|wheat)/,`Poland ${crop}`);
  });
  document.querySelectorAll('[data-plot-link]').forEach(link=>link.href=`assets/plots/${crop}/${link.dataset.plotLink}.png`);
  document.querySelectorAll('[data-plot-download]').forEach(link=>{
    const [name,ext]=link.dataset.plotDownload.split(':');link.href=`assets/plots/${crop}/${name}.${ext}`;
  });
  element('parameter-table').innerHTML=table(['Method','Tuning-selected parameters','Interval half-width'],run.selected_hyperparameters.map(r=>row([escapeHTML(labels[r.Method]),escapeHTML(r.Parameters),format(r.IntervalHalfWidth)],r.Method===selected)));
  metrics();predictions();
}

fetch('assets/data/poland.json').then(response=>{
  if(!response.ok) throw new Error('Results could not be loaded');return response.json();
}).then(data=>{
  runs=data;
  updateCrop(new URLSearchParams(location.search).get('crop')==='wheat'?'wheat':'barley');
  document.querySelectorAll('select,[data-crop]').forEach(control=>control.disabled=false);
  document.querySelectorAll('[data-crop]').forEach(button=>button.addEventListener('click',()=>updateCrop(button.dataset.crop)));
  document.querySelectorAll('[data-crop]').forEach(button=>button.addEventListener('keydown',event=>{
    if(!['ArrowLeft','ArrowRight','Home','End'].includes(event.key)) return;
    event.preventDefault();
    const next=event.key==='Home'?'barley':event.key==='End'?'wheat':crop==='barley'?'wheat':'barley';
    updateCrop(next);document.querySelector(`[data-crop="${next}"]`).focus();
  }));
  element('metric-level').addEventListener('change',metrics);
  element('chart-method').addEventListener('change',predictions);
  element('chart-region').addEventListener('change',predictions);
  element('load-status').textContent='Results loaded from the completed YieldLag 0.2.0 runs.';
}).catch(error=>{
  element('load-status').innerHTML='<div class="error-message">Interactive results could not be loaded. The figures and downloads are available below. Open the <a href="barley.html">static barley report</a> or <a href="wheat.html">static wheat report</a> for complete results.</div>';
  document.querySelectorAll('select,[data-crop]').forEach(control=>control.disabled=true);
});
