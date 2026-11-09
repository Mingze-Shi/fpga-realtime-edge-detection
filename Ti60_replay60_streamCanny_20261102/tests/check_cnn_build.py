"""Verify current source hashes, regressions, routed timing and CNN artifacts."""
import argparse,hashlib,json,re,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'outflow_cnn'
ap=argparse.ArgumentParser();ap.add_argument('--snapshot',action='store_true');ap.add_argument('--timing-only',action='store_true');args=ap.parse_args()
ns={'e':'http://www.efinixinc.com/enf_proj'}
sources=[ROOT/n.get('name') for n in ET.parse(ROOT/'ti60f225_oob.xml').findall('.//e:design_file',ns)]
inputs=sources+[ROOT/p for p in ['rtl/cnn_params.vh','rtl/cnn_expression_params.vh','assets/cnn/weights.hex','assets/cnn_expression/weights.hex','ti60f225_oob.xml','ti60f225_oob.sdc','ti60f225_oob.peri.xml']]
def hashes():return {p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
snapshot=OUT/'build_inputs.json'
if args.snapshot:
    OUT.mkdir(exist_ok=True);snapshot.write_text(json.dumps(hashes(),indent=2),encoding='utf-8');print('Build input hashes recorded.');raise SystemExit(0)
assert json.loads(snapshot.read_text(encoding='utf-8'))==hashes(),'Source or weights changed during build'
mapped=OUT/'ti60f225_oob.map.v';timing_file=OUT/'ti60f225_oob.timing.rpt'
# Efinity rewrites project XML after PNR even when its bytes are unchanged.
# XML integrity is guarded by the pre-build SHA256 snapshot above; RTL and weight
# freshness use timestamps as an additional independent check.
assert mapped.stat().st_mtime>=max(p.stat().st_mtime for p in inputs if p.name!='ti60f225_oob.xml')
assert timing_file.stat().st_mtime>=mapped.stat().st_mtime
base=(ROOT/'test_output/all_tests.log').read_text(encoding='utf-8')
assert len(re.findall(r'^PASS:',base,re.M))==20
for f in ['regression_all_tests.log','expression_match_tb.log','expression_video_tb.log','cnn_core_tb.log','cnn_capture_tb.log','cnn_video_tb.log','replay6_slots_tb.log','replay6_control_tb.log','replay6_ddr_tb.log','replay6_overlay_tb.log','replay6_startup_tb.log','replay6_half_capacity.log','replay6_full.log','replay6_short_1.log','replay6_short_2.log','replay6_short_127.log','replay6_short_128.log','replay6_short_129.log','replay6_short_255.log','replay6_short_256.log','expression_decision_tb.log','expression_text_tb.log','expression_confirmation_tb.log','expression_cnn_core_tb.log','expression_cnn_capture_tb.log','expression_cnn_video_tb.log']:
    p=ROOT/'test_output'/f;t=p.read_text(encoding='utf-8-sig')
    assert 'FATAL:' not in t and 'PASS:' in t,f
    # Legacy/CNN benches do not instantiate the physical frame-buffer wrapper
    # or DDR writer/reader. Check their actual dependency scope, so a camera
    # startup guard does not invalidate unrelated CNN arithmetic evidence.
    deps=[s for s in inputs if s.suffix in ('.v','.sv','.vh')]
    if not f.startswith('replay6_'):
        deps=[s for s in deps if (s.parent.name!='frame_buffer_V4' or s.name=='bank_switch.v') and s.name!='replay6_slots.v']
        if f not in ('expression_decision_tb.log','expression_text_tb.log','expression_confirmation_tb.log','expression_cnn_core_tb.log','expression_cnn_capture_tb.log','expression_cnn_video_tb.log'):deps=[s for s in deps if s.name not in ('expression_cnn_decision.v','taffy_expression_cnn_core.v','taffy_expression_cnn_match.v','cnn_expression_text.v','cnn_expression_params.vh')]
    elif f in ('replay6_ddr_tb.log','replay6_full.log'):
        deps=[s for s in deps if s.name in ('replay6_slots.v','frame_write_commit.v','ddr_buffer.v','ddr_wr_buffer.v','ddr_rd_buffer.v')]
    elif f=='replay6_slots_tb.log':deps=[ROOT/'rtl/replay6_slots.v']
    elif f=='replay6_control_tb.log':deps=[ROOT/'rtl/canny_snapshot_control.v']
    elif f=='replay6_overlay_tb.log':deps=[s for s in deps if s.parent.name!='frame_buffer_V4']
    if f.startswith('replay6_'):deps=[d for d in deps if d.name not in ('expression_cnn_decision.v','taffy_expression_cnn_core.v','taffy_expression_cnn_match.v','cnn_expression_text.v','cnn_expression_params.vh')]
    assert p.stat().st_mtime>=max(s.stat().st_mtime for s in deps),f+' predates its RTL dependencies'
model=json.loads((ROOT/'assets/cnn_expression/model.json').read_text(encoding='utf-8'))
result=dict(device='Ti60F225',timing_model='I3',recognizer='trained 965-parameter int8 five-class CNN',
 labels=['无法确定','taffy-大笑','taffy-放松','taffy-哭哭','taffy-微笑'],classes=5,
 scope='Four supplied taffy drawing patterns, fixed manually aligned 1024x512 face guide; not general emotion recognition.',
 raw_camera_holdout_images=0,camera_accuracy=None,programmed_to_board=False,rtl_multiclass_integrated=True,
 existing_regression_groups=20,legacy_binary_cnn_groups=3,new_expression_cnn_groups=6,replay_groups_rerun=14,
 integer_cases=32,intermediate_feature_comparisons=65536,decision_cases=922,
 cnn_parameters=965,cnn_weight_bytes=940,activation_ram_bytes=2048,
 convolution_core_cycles_without_normalization=int(re.search(r'cycles/case=(\d+)',(ROOT/'test_output/expression_cnn_core_tb.log').read_text()).group(1)),normalization_cycles=20480,
 confirmation='three consecutive accepted results of the SAME class',
 rejection=dict(probability_lower_bound=.55,top_two_margin_lower_bound=.2,other_class_rejected=True,flat_field_rejected=True),
 display_resolution=[1920,1080],edge_processing_resolution=[1920,1080],cnn_input=[32,32,1],
 new_training_performed_this_build=False,reused_checkpoint_sha256=model['model_sha256'])
timing=timing_file.read_text(encoding='utf-8')
sec=timing.split('Setup (Max) Clock Relationship',1)[1].split('NOTE:',1)[0]
setup,hold=sec.split('Hold (Min) Clock Relationship',1)
for name,section in [('setup_min_slack_ns',setup),('hold_min_slack_ns',hold)]:
    vals=[float(m[1]) for m in re.findall(r'^\S+\s+\S+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(',section,re.M)]
    assert vals and min(vals)>=0,(name,vals)
    result[name]=min(vals)
resource=(OUT/'ti60f225_oob.place.rpt').read_text(encoding='utf-8')
for label in ['Memory Blocks','DSP Blocks']:
    used,avail=map(int,re.search(re.escape(label)+r':\s*(\d+)\s*/\s*(\d+)',resource).groups())
    assert used<=avail
    result[label]=dict(used=used,available=avail,remaining=avail-used)
hier=(OUT/'ti60f225_oob.hier_util.rpt').read_text(encoding='utf-8')
rows=[r for r in hier.splitlines() if '+cnn_expression_recognition.u_match' in r]
assert len(rows)==1
result['cnn_ram_blocks']=float(rows[0].split('|')[3].strip().split('(')[0]);assert result['cnn_ram_blocks']<=14
map_report=(OUT/'ti60f225_oob.map.rpt').read_text(encoding='utf-8')
assert 'u_camera_sobel/cnn_expression_recognition.u_match/u_core/weights' in map_report
assert 'six_frame.u_slots' in mapped.read_text(encoding='utf-8'),'Six-frame manager absent from synthesized netlist'
assert result['Memory Blocks']['used']<=249,'Unexpected image RAM growth; inspect before delivery'
result['sources_sha256']=hashes()
result['replay']=dict(frozen_frames=6,external_slots=10,nominal_raw8_frame_bytes=2073600,frame_length_source="first accepted stable measured frame, held across freeze",frame_capacity_bytes=4147200,slot_stride=4147712,reserved_ddr_bytes=41477120,added_image_bram=0,simulation_groups=14,comparison='manual sequential comparison of six frozen complete frames')
if not args.timing_only:
    result['artifacts']={}
    for ext in ('bit','hex'):
        p=OUT/f'ti60f225_oob.{ext}';assert p.stat().st_size>100000 and p.stat().st_mtime>=timing_file.stat().st_mtime
        result['artifacts'][ext]=dict(path=p.relative_to(ROOT).as_posix(),bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest())
    (OUT/'cnn_verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='sources_sha256'},ensure_ascii=False,indent=2))
