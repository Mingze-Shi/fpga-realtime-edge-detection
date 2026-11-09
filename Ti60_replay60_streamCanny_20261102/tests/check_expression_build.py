"""Gate programming artifacts on fresh simulation, routed timing, and RAM budget."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outflow_expression'
parser=argparse.ArgumentParser();parser.add_argument('--timing-only',action='store_true');args=parser.parse_args()
ns={'e':'http://www.efinixinc.com/enf_proj'}
sources=[ROOT/n.get('name') for n in ET.parse(ROOT/'ti60f225_oob.xml').findall('.//e:design_file',ns)]
assets=[ROOT/'assets/expressions/templates.hex',ROOT/'assets/expressions/model.json',ROOT/'assets/expressions/label_masks.hex']
constraints=[ROOT/'ti60f225_oob.sdc',ROOT/'ti60f225_oob.peri.xml']
inputs=sources+assets+constraints
assert all(p.exists() for p in inputs)
mapped=OUT/'ti60f225_oob.map.v';timing_file=OUT/'ti60f225_oob.timing.rpt'
assert mapped.stat().st_mtime>=max(p.stat().st_mtime for p in sources+assets),'Map predates current HDL/assets'
assert timing_file.stat().st_mtime>=max(p.stat().st_mtime for p in inputs),'Routed timing predates source/constraints'
assert timing_file.stat().st_mtime>=mapped.stat().st_mtime
logs=[ROOT/'test_output/regression_all_tests.log',ROOT/'test_output/expression_match_tb.log',ROOT/'test_output/expression_video_tb.log']
for p in logs:
    assert p.stat().st_mtime>=max(s.stat().st_mtime for s in sources),'Simulation log predates RTL'
    assert 'FATAL:' not in p.read_text(encoding='utf-8-sig')
text=(ROOT/'test_output/all_tests.log').read_text(encoding='utf-8')
assert len(re.findall(r'^PASS:',text,re.M))==20
assert '69 cases and all best/second scores' in text
assert '307200 samples, 307200 complete-map BFS comparisons' in text
timing=timing_file.read_text(encoding='utf-8')
sections=timing.split('Setup (Max) Clock Relationship',1)[1].split('NOTE:',1)[0]
setup,hold=sections.split('Hold (Min) Clock Relationship',1)
result={'device':'Ti60F225/I3','recognizer':'4-bit masked DC-compensated SAD template classification',
        'trained_neural_network':False,'classes':4,'simulation_test_groups_passed':20,
        'synthetic_software_cases':69,'camera_holdout_accuracy':None,'programmed_to_board':False,
        'scope':'four supplied face patterns, fixed manually aligned 512x256 guide; not general emotion/identity recognition',
        'processing_resolution':[640,480],'display_resolution':[1920,1080],
        'raw_template_bits':16384,'recognizer_ping_pong_bits':8192,
        'shared_engine_cycles':204805,'shared_engine_time_ms_at_148_5MHz':round(204805/148500,4)}
for name,section in [('setup_min_slack_ns',setup),('hold_min_slack_ns',hold)]:
    values=[float(m[1]) for m in re.findall(r'^\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(',section,re.M)]
    assert values and min(values)>=0,f'{name}: {min(values) if values else "missing"}'
    result[name]=min(values)
resource=(OUT/'ti60f225_oob.place.rpt').read_text(encoding='utf-8')
for label in ['Memory Blocks','DSP Blocks']:
    used,available=map(int,re.search(re.escape(label)+r':\s*(\d+)\s*/\s*(\d+)',resource).groups())
    assert used<=available
    result[label]={'used':used,'available':available,'remaining':available-used}
hier=(OUT/'ti60f225_oob.hier_util.rpt').read_text(encoding='utf-8')
row=[r for r in hier.splitlines() if '+expression_recognition.u_match' in r]
assert len(row)==1,'Expression recognizer not in final synthesized hierarchy'
recognizer_ram=float(row[0].split('|')[3].strip().split('(')[0])
assert recognizer_ram<=14,'Recognizer exceeds the requested 14-block ceiling'
result['recognizer_ram_blocks']=recognizer_ram
assert result['Memory Blocks']['used']<=256
result['sources_sha256']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs+[ROOT/'ti60f225_oob.xml']}
if not args.timing_only:
    result['artifacts']={}
    for ext in ('bit','hex'):
        p=OUT/f'ti60f225_oob.{ext}'
        assert p.stat().st_size>100000 and p.stat().st_mtime>=timing_file.stat().st_mtime
        result['artifacts'][ext]={'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'bytes':p.stat().st_size}
    (OUT/'expression_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='sources_sha256'},ensure_ascii=False,indent=2))
