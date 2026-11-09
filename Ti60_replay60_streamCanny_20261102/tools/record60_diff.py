from pathlib import Path
import difflib,json,hashlib
r=Path.cwd();base=Path(r'D:/efinity_project/program_Ti60_CNN1_20261101/Ti60_CNN')
changed=[];patch=[]
for p in (r/'rtl').rglob('*'):
 if not p.is_file():continue
 q=base/p.relative_to(r)
 if q.exists() and p.read_bytes()!=q.read_bytes():
  changed.append(str(p.relative_to(r)));patch+=difflib.unified_diff(q.read_bytes().decode('latin1').splitlines(True),p.read_bytes().decode('latin1').splitlines(True),fromfile='before/'+p.relative_to(r).as_posix(),tofile='after/'+p.relative_to(r).as_posix())
(r/'REPLAY60.patch').write_text(''.join(patch),encoding='utf-8')
print(json.dumps(changed));print('DDR reserved bytes',64*4147712,'of',256*1024*1024)
