from pathlib import Path
import re,json
root=Path(__file__).resolve().parents[1]
s=(root/'outflow_cnn/ti60f225_oob.map.v').read_text(encoding='utf-8')
loops=[]
for m in re.finditer(r'EFX_LUT\d\s+(\S+)\s*\((.*?)\)\s*/\*',s,re.S):
 body=m.group(2);out=re.search(r'\.O\(([^)]+)\)',body)
 if out and re.search(r'\.I\d\('+re.escape(out.group(1))+r'\)',body):loops.append(m.group(1))
r={'direct_lut_self_feedback_cells':loops,'six_frame_hierarchy_present':'six_frame.u_slots' in s}
(root/'outflow_cnn/replay6_netlist_check.json').write_text(json.dumps(r,indent=2),encoding='utf-8')
assert not loops,loops
assert r['six_frame_hierarchy_present']
print('PASS: synthesized six-frame hierarchy present; zero direct LUT self-feedback cells')
