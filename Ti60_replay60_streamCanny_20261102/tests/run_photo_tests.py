"""Run photo matcher and video integration against the supplied reference."""
import os
from pathlib import Path
import subprocess
from run_canny_tests import simulator

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
temporary=ROOT/'test_output/tmp'
temporary.mkdir(parents=True,exist_ok=True)
os.environ['TMPDIR']=os.environ['TMP']=os.environ['TEMP']=str(temporary)
compiler,runtime=simulator()
os.environ['PATH']=os.pathsep.join((str(compiler.parent),str(compiler.parent.parent/'mingw-w64/bin'),os.environ['PATH']))
sources=['rtl/taffy_template_rom.v','rtl/taffy_photo_match.v','rtl/taffy_success_text.v']
for test in ['taffy_photo_tb','taffy_video_tb']:
    extra=['rtl/sc431_sobel_video.v','rtl/mode_key.v','rtl/threshold_keys.v',
           'rtl/median3x3.v','rtl/sobel_stream.v'] if test=='taffy_video_tb' else []
    target=ROOT/'test_output'/f'{test}.vvp'
    subprocess.run([str(compiler),'-g2012','-Wall','-s',test,'-o',str(target),*sources,*extra,f'tests/{test}.v'],check=True)
    result=subprocess.run([str(runtime),str(target)],capture_output=True,text=True)
    (ROOT/'test_output'/f'{test}.log').write_text(result.stdout+result.stderr,encoding='utf-8')
    print(result.stdout,end='')
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
