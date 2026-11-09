from pathlib import Path
import os,subprocess,sys
from run_canny_tests import simulator
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT);OUT=ROOT/'test_output';OUT.mkdir(exist_ok=True)
c,v=simulator();os.environ['PATH']=str(c.parent.parent/'mingw-w64/bin')+os.pathsep+os.environ['PATH']
sources=['rtl/expression_cnn_decision.v','rtl/taffy_expression_cnn_core.v','rtl/taffy_expression_cnn_match.v','rtl/cnn_expression_text.v']
names=sys.argv[1:] or ['expression_decision_tb','expression_text_tb','expression_confirmation_tb','expression_cnn_core_tb','expression_cnn_capture_tb','expression_cnn_video_tb']
for name in names:
 src=sources.copy()
 if name=='expression_cnn_video_tb':src+=['rtl/sc431_sobel_video.v','rtl/mode_key.v','rtl/threshold_keys.v','rtl/median3x3.v','rtl/sobel_stream.v']
 target=OUT/(name+'.vvp')
 subprocess.run([str(c),'-g2012','-s',name,'-o',str(target),*src,'tests/'+name+'.v'],check=True)
 r=subprocess.run([str(v),str(target)],capture_output=True,text=True)
 (OUT/(name+'.log')).write_text(r.stdout+r.stderr,encoding='utf-8');print(r.stdout,flush=True)
 if r.returncode:print(r.stderr);sys.exit(r.returncode)
