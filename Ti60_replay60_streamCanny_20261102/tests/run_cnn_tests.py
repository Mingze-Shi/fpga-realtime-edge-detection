import os,subprocess,json,sys
from pathlib import Path
from run_canny_tests import simulator
ROOT=Path(__file__).resolve().parents[1];os.chdir(ROOT)
OUT=ROOT/'test_output';OUT.mkdir(exist_ok=True)
tmp=OUT/'tmp';tmp.mkdir(exist_ok=True)
os.environ['TMP']=os.environ['TEMP']=os.environ['TMPDIR']=str(tmp)
compiler,runtime=simulator()
os.environ['PATH']=os.pathsep.join((str(compiler.parent),str(compiler.parent.parent/'mingw-w64/bin'),os.environ['PATH']))
for name in (sys.argv[1:] or ['cnn_core_tb','cnn_capture_tb','cnn_video_tb']):
    tb=ROOT/f'tests/{name}.v'
    if not tb.exists():raise SystemExit(f'Missing required testbench: {tb}')
    output=OUT/f'{name}.vvp'
    sources=['rtl/taffy_cnn_core.v','rtl/taffy_cnn_match.v','rtl/cnn_status_text.v']
    sources=[p for p in sources if (ROOT/p).exists()]
    if name=='cnn_video_tb':sources+=['rtl/sc431_sobel_video.v','rtl/mode_key.v','rtl/threshold_keys.v','rtl/median3x3.v','rtl/sobel_stream.v']
    subprocess.run([str(compiler),'-g2012','-Wall','-s',name,'-o',str(output),*sources,str(tb)],check=True)
    r=subprocess.run([str(runtime),str(output)],capture_output=True,text=True)
    (OUT/f'{name}.log').write_text(r.stdout+r.stderr,encoding='utf-8')
    print(r.stdout,flush=True)
    if r.returncode:print(r.stderr);raise SystemExit(r.returncode)
