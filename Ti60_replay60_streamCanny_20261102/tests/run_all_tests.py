"""Run existing regression suite unchanged, plus expression checks; collect evidence."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'test_output';OUT.mkdir(exist_ok=True)
parser=argparse.ArgumentParser();parser.add_argument('--collect',action='store_true');args=parser.parse_args()
os.chdir(ROOT)
os.environ['PATH']=str(Path(sys.executable).parent)+os.pathsep+os.environ['PATH']
if not args.collect:
    commands=[('regression_all_tests.log',['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File','run_tests.ps1']),
              ('expression_tests.log',[sys.executable,'-X','utf8','tests/run_expression_tests.py'])]
    for filename,command in commands:
        result=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace')
        (OUT/filename).write_text(result.stdout+result.stderr,encoding='utf-8')
        print(result.stdout,flush=True)
        if result.returncode:
            print(result.stderr);raise SystemExit(result.returncode)
logs=[OUT/'regression_all_tests.log',OUT/'expression_match_tb.log',OUT/'expression_video_tb.log']
text='\n'.join(p.read_text(encoding='utf-8-sig') for p in logs)
assert not re.search(r'FATAL:|Traceback \(most recent call last\)',text),'Simulation failure in evidence logs'
passes=re.findall(r'^PASS:.*$',text,re.M)
assert len(passes)==20,f'Expected 17 regression and 3 expression groups, got {len(passes)}'
(OUT/'all_tests.log').write_text('\n'.join(passes)+'\n',encoding='utf-8')
print('\n'.join(passes))
print('All 20 test groups passed. Synthetic checks do not establish camera accuracy.')
