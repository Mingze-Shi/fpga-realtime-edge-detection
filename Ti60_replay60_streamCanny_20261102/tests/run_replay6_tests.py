from pathlib import Path
import os,subprocess,sys
from run_canny_tests import simulator
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
OUT=ROOT/'test_output';OUT.mkdir(exist_ok=True)
c,v=simulator();os.environ['PATH']=str(c.parent.parent/'mingw-w64/bin')+os.pathsep+os.environ['PATH']
tests={'replay6_slots_tb':['rtl/replay6_slots.v'],'replay6_control_tb':['rtl/canny_snapshot_control.v']}
tests['replay6_autoplay_tb']=['rtl/canny_snapshot_control.v']
tests['replay6_ddr_tb']=['rtl/replay6_slots.v','rtl/frame_write_commit.v','rtl/frame_buffer_V4/ddr_buffer.v','rtl/frame_buffer_V4/ddr_wr_buffer.v','rtl/frame_buffer_V4/ddr_rd_buffer.v']
tests['replay6_overlay_tb']=['rtl/replay6_slots.v',*[str(p.relative_to(ROOT)) for p in (ROOT/'rtl').glob('canny_*.v')],'rtl/median3x3.v','rtl/sobel_stream.v','rtl/threshold_keys.v','rtl/mode_key.v','rtl/sc431_sobel_video.v']
tests['replay6_startup_tb']=[*tests['replay6_ddr_tb'],'tests/replay6_ddr_tb.v','rtl/frame_buffer_V4/frame_buffer.v','rtl/frame_buffer_V4/vid_rx_align_v1.v','rtl/frame_buffer_V4/frame_info_det.v','rtl/frame_buffer_V4/ser2par_v1.v','rtl/frame_buffer_V4/rst_n_piple.v','rtl/frame_buffer_V4/vid_par2ser.v']
from run_canny_tests import fixtures
fixtures()
for name,src in tests.items():
 target=OUT/(name+'.vvp')
 subprocess.run([str(c),'-g2012','-s',name,'-o',str(target),*src,'tests/'+name+'.v'],check=True)
 r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
 (OUT/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout,flush=True)
 if r.returncode:print(r.stderr);sys.exit(r.returncode)

name='replay6_overlay_tb';target=OUT/'replay6_autoplay_overlay.vvp'
subprocess.run([str(c),'-g2012','-s',name,'-P'+name+'.AUTO=1','-o',str(target),*tests[name],'tests/'+name+'.v'],check=True)
r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
(OUT/'replay6_autoplay_overlay.log').write_text(r.stdout+r.stderr,encoding='utf-8');print('Autoplay overlay: '+r.stdout,flush=True)
if r.returncode:print(r.stderr);sys.exit(r.returncode)

# The physical camera packs four RAW8 pixels per 32-bit input beat. A full
# frame can therefore occupy half the former capacity-based length assumption.
name='replay6_startup_tb';target=OUT/'replay6_half_capacity.vvp'
subprocess.run([str(c),'-g2012','-s',name,'-P'+name+'.INPUT_BEATS=512','-o',str(target),*tests[name],'tests/'+name+'.v'],check=True)
r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
(OUT/'replay6_half_capacity.log').write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout,flush=True)
if r.returncode:print(r.stderr);sys.exit(r.returncode)

for words in (1,2,127,128,129,255,256):
 name='replay6_ddr_tb';target=OUT/('replay6_short_'+str(words)+'.vvp')
 subprocess.run([str(c),'-g2012','-s',name,'-P'+name+'.FRAME_WORDS='+str(words),'-P'+name+'.SIMPLE=1','-o',str(target),*tests[name],'tests/'+name+'.v'],check=True)
 r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
 (OUT/('replay6_short_'+str(words)+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8');print(str(words)+' words: '+r.stdout,flush=True)
 if r.returncode:print(r.stderr);sys.exit(r.returncode)

if '--full' in sys.argv:
 name='replay6_ddr_tb';target=OUT/'replay6_full.vvp'
 subprocess.run([str(c),'-g2012','-s',name,'-P'+name+'.FULL=1','-o',str(target),*tests[name],'tests/'+name+'.v'],check=True)
 r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
 (OUT/'replay6_full.log').write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout,flush=True)
 if r.returncode:sys.exit(r.returncode)
