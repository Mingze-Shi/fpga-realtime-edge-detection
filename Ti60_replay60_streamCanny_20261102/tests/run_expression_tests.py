"""Regenerate software golden vectors, then compare actual RTL and video output."""
import os
from pathlib import Path
import subprocess
import sys
from run_canny_tests import simulator

ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
subprocess.run([sys.executable,'-X','utf8','tools/validate_expressions.py'],check=True)
compiler,runtime=simulator()
temporary=ROOT/'test_output/tmp';temporary.mkdir(parents=True,exist_ok=True)
os.environ['TMP']=os.environ['TEMP']=os.environ['TMPDIR']=str(temporary)
os.environ['PATH']=os.pathsep.join((str(compiler.parent),str(compiler.parent.parent/'mingw-w64/bin'),os.environ['PATH']))
tests=['expression_video_tb'] if '--video-only' in sys.argv else ['expression_match_tb','expression_video_tb']
for test in tests:
    sources=['rtl/taffy_expression_match.v']
    if test=='expression_video_tb':
        sources+=['rtl/taffy_expression_text.v','rtl/sc431_sobel_video.v','rtl/mode_key.v','rtl/threshold_keys.v',
                  'rtl/median3x3.v','rtl/sobel_stream.v']
    target=ROOT/f'test_output/{test}.vvp'
    subprocess.run([str(compiler),'-g2012','-Wall','-s',test,'-o',str(target),*sources,f'tests/{test}.v'],check=True)
    result=subprocess.run([str(runtime),str(target)],capture_output=True,text=True)
    (ROOT/f'test_output/{test}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    print(result.stdout,end='',flush=True)
    if result.returncode:
        print(result.stderr);raise SystemExit(result.returncode)
