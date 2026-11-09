"""Check final routed timing and source freshness; never programs hardware."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'outflow_canny'
parser = argparse.ArgumentParser()
parser.add_argument('--timing-only', action='store_true')
args = parser.parse_args()
ns = {'e': 'http://www.efinixinc.com/enf_proj'}
sources = [ROOT/n.get('name') for n in ET.parse(ROOT/'ti60f225_oob.xml').findall('.//e:design_file', ns)]
template_inputs = [ROOT/'assets/taffy/contour_patches.hex',ROOT/'assets/taffy/contour_template.json',ROOT/'assets/taffy/gray.hex',
                   ROOT/'assets/taffy/template.json',ROOT/'assets/taffy/success_text_mask.hex']
inputs = sources + template_inputs + [ROOT/'ti60f225_oob.xml', ROOT/'ti60f225_oob.sdc', ROOT/'ti60f225_oob.peri.xml']
assert all(p.is_file() for p in inputs)
timing_file = OUT/'ti60f225_oob.timing.rpt'
mapped_file = OUT/'ti60f225_oob.map.v'
# Efinity rewrites the project XML at the end of each flow, after its reports.
# Check HDL/constraints timestamps; record the current XML hash separately.
assert mapped_file.stat().st_mtime >= max(p.stat().st_mtime for p in sources+template_inputs), 'Synthesized netlist predates HDL/template changes'
assert timing_file.stat().st_mtime >= max(p.stat().st_mtime for p in inputs if p.suffix != '.xml' or p.name.endswith('.peri.xml')), 'Routed timing predates source/constraint changes'
assert timing_file.stat().st_mtime >= mapped_file.stat().st_mtime, 'Routed timing predates synthesis'
timing = timing_file.read_text(encoding='utf-8')
sections = timing.split('Setup (Max) Clock Relationship', 1)[1].split('NOTE:', 1)[0]
setup, hold = sections.split('Hold (Min) Clock Relationship', 1)
result = {'processing_resolution': [1920, 1080], 'display_resolution': [1920, 1080],
          'hysteresis': 'local 3x3 on a 1 px/clk streaming pipeline; one result per frame',
          'programmed_to_board': False}
simulation_log = ROOT/'test_output/all_tests.log'
simulation_text = simulation_log.read_text(encoding='utf-8')
assert 'FATAL:' not in simulation_text and 'Traceback' not in simulation_text, 'Simulation errors in final log'
assert len(re.findall(r'^PASS:', simulation_text, re.M)) == 17, 'Expected all seventeen simulation cases to pass'
assert 'PASS: partial-contour exact/brightness/contrast' in simulation_text
assert 'PASS: photo matcher video integration' in simulation_text
assert '307200 samples, 307200 complete-map BFS comparisons' in simulation_text, 'Actual 640x480 test missing'
assert simulation_log.stat().st_mtime >= max(p.stat().st_mtime for p in sources+template_inputs), 'Simulations predate HDL/template changes'
result['simulation_cases_passed'] = 17
result['fixed_photo_recognition'] = '64x64 samples pooled to 16x16 contours; any detailed 6x6 patch matches any reference patch; three-frame confirmation'
result['photo_patch_bit_mismatch_limit'] = json.loads(
    (ROOT/'assets/taffy/contour_template.json').read_text(encoding='utf-8'))['max_bit_mismatches']
result['photo_patch_cells'] = 36
result['template_rom_bits'] = 33*36
result['recognition_success_text'] = '\u5173\u6ce8\u5854\u83f2\u55b5'
result['photo_hardware_validated'] = False
result['overlay_mode'] = 'same-frame DDR snapshot with red edges'
result['replay'] = 'two retained RAW slots, manual previous/next, third slot continues capture'
result['additional_image_storage_bits'] = 0
for key, section in [('setup_min_slack_ns', setup), ('hold_min_slack_ns', hold)]:
    values = [float(m[1]) for m in re.findall(r'^\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(', section, re.M)]
    assert values and min(values) >= 0, f'{key}: {min(values) if values else "no timing rows"}'
    result[key] = min(values)
resource = (OUT/'ti60f225_oob.place.rpt').read_text(encoding='utf-8')
for label in ['Memory Blocks', 'DSP Blocks']:
    used, available = map(int, re.search(re.escape(label)+r':\s*(\d+)\s*/\s*(\d+)', resource).groups())
    assert used <= available, label
    result[label] = {'used': used, 'available': available}
hierarchy = (OUT/'ti60f225_oob.hier_util.rpt').read_text(encoding='utf-8')
commit_rows = [line for line in hierarchy.splitlines() if '+u_frame_commit' in line]
assert len(commit_rows)==1
metadata_bram = float(commit_rows[0].split('|')[3].strip().split('(')[0])
assert metadata_bram == 0, 'Frame metadata must stay in registers, not consume BRAM'
# Overlay/replay still use existing DDR slots; only the new reference ROM adds storage.
assert result['Memory Blocks']['used'] <= 256, 'Photo template must fit available device RAM'
result['metadata_bram_blocks'] = 0
photo_rows = [line for line in hierarchy.splitlines() if '+photo_recognition.u_match' in line]
assert len(photo_rows)==1, 'Photo matcher missing from synthesized top'
result['photo_matcher_bram_blocks'] = float(photo_rows[0].split('|')[3].strip().split('(')[0])
assert 0 <= result['photo_matcher_bram_blocks'] <= 14, 'Template ROM must fit remaining RAM'
result['additional_bram_blocks_vs_baseline'] = result['Memory Blocks']['used']-242
assert 'CANNY_ENABLE(1)' in (ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8')
assert '.CANNY_WIDTH(640),.CANNY_HEIGHT(480)' in (ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8')
assert '.SNAPSHOT_ENABLE(1)' in (ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8')
assert '.PHOTO_MATCH_ENABLE(1)' in (ROOT/'rtl/ti60f225_oob_top.v').read_text(encoding='utf-8')
result['sources_sha256'] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
if not args.timing_only:
    result['artifacts'] = {}
    for ext in ('bit', 'hex'):
        artifact = OUT / f'ti60f225_oob.{ext}'
        assert artifact.stat().st_size > 100000
        assert artifact.stat().st_mtime >= timing_file.stat().st_mtime
        result['artifacts'][ext] = {'path': str(artifact), 'sha256': hashlib.sha256(artifact.read_bytes()).hexdigest()}
    (OUT/'canny_verification.json').write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(json.dumps({k: v for k, v in result.items() if k != 'sources_sha256'}, indent=2))
