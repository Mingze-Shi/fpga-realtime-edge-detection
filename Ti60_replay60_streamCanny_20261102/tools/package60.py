from pathlib import Path
import hashlib,json,re,zipfile
r=Path.cwd();o=r/'outflow_cnn'
log=(r/'build60.log').read_text(encoding='utf-8-sig',errors='replace');assert all(re.search(x+r'\s*:\s*PASS',log) for x in ['map','interface','pnr','pgm'])
t=(o/'ti60f225_oob.timing.rpt').read_text();parts=[t.split('Setup (Max) Clock Relationship')[1].split('Hold (Min)')[0],t.split('Hold (Min) Clock Relationship')[1].split('NOTE:')[0]]
mins=[min(float(m[1]) for m in re.findall(r'^\S+\s+\S+\s+([-\d.]+)\s+([-\d.]+)\s+\(R-R\)',s,re.M)) for s in parts];assert min(mins)>=0
report=dict(device='Ti60F225',timing_model='I3',replay_frames=60,slots=64,ddr_reserved_bytes=265453568,memory_blocks=249,lut4=29530,flip_flops=12564,dsp_blocks=62,setup_min_slack_ns=mins[0],hold_min_slack_ns=mins[1],programmed_to_board=False,physical_hdmi_verified=False,full_resolution_simulation_run=False,artifacts={})
for ext in ['bit','hex']:
 p=o/('ti60f225_oob.'+ext);report['artifacts'][ext]=dict(path=p.relative_to(r).as_posix(),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),bytes=p.stat().st_size)
for p in [r/'replay60_verification.json',o/'cnn_verification.json',r/'programming_record.json']:
 p.write_text(json.dumps(report,indent=2),encoding='utf-8')
(r/'README_REPLAY60.md').write_text((r/'README_REPLAY60.md').read_text(encoding='utf-8-sig')+'\n编译：Map、Interface、PnR、PGM通过。最小建立裕量+0.415ns，保持裕量+0.026ns；LUT4 29530，FF 12564，RAM 249，DSP 62。\n',encoding='utf-8')
files=[p for p in r.rglob('*') if p.is_file() and not any(x in p.relative_to(r).parts for x in ['work_pnr','work_syn','__pycache__','.git']) and p.suffix not in ['.vvp','.pyc'] and p.name not in ['MANIFEST.sha256','DELIVERY_MANIFEST.json']]
(r/'MANIFEST.sha256').write_text('\n'.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.relative_to(r).as_posix() for p in files),encoding='utf-8');files.append(r/'MANIFEST.sha256')
dest=Path(r'C:/Users/duodu/OneDrive/Desktop/Ti60_60帧冻帧回放_20261101.zip')
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=5) as z:
 for p in files:z.write(p,'Ti60_replay60/'+p.relative_to(r).as_posix())
with zipfile.ZipFile(dest) as z:assert z.testzip() is None
print(dest);print(dest.stat().st_size);print(json.dumps(report))
