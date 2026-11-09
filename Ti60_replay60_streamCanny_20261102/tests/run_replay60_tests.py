from pathlib import Path
import re,os,subprocess,sys
r=Path.cwd();sys.path.insert(0,str(r/'tests'));from run_canny_tests import simulator
c,v=simulator();os.environ['PATH']=str(c.parent.parent/'mingw-w64/bin')+os.pathsep+os.environ['PATH'];o=r/'test_output';o.mkdir(exist_ok=True)
s=(r/'tests/replay6_slots_tb.v').read_text();s=s.replace('replay6_slots_tb','replay60_slots_tb').replace('[2:0]','[5:0]').replace('[3:0]','[5:0]').replace('reading=9','reading=63').replace('[0:9]','[0:63]').replace('[0:5]','[0:59]').replace('.STRIDE(4608)','.STRIDE(4608),.HISTORY_FRAMES(60)');s=re.sub(r'\b6\b','60',s);s=s.replace('5-n','59-n').replace('n<10','n<64').replace('k<18','k<180');(r/'tests/replay60_slots_tb.v').write_text(s)
s=(r/'tests/replay6_autoplay_tb.v').read_text().replace('replay6_autoplay_tb','replay60_autoplay_tb').replace('[2:0]','[5:0]').replace('.REPLAY_FRAMES(6)','.REPLAY_FRAMES(60)').replace('sel!=5','sel!=59').replace('n=5','n=59').replace('sel!=4','sel!=58').replace('#200000;','#2000000;');(r/'tests/replay60_autoplay_tb.v').write_text(s)
for name,src in [('replay60_slots_tb','rtl/replay6_slots.v'),('replay60_autoplay_tb','rtl/canny_snapshot_control.v')]:
 subprocess.run([str(c),'-g2012','-s',name,'-o',str(o/(name+'.vvp')),src,'tests/'+name+'.v'],check=True)
 x=subprocess.run([str(v),str(o/(name+'.vvp'))],capture_output=True,text=True);print(name,x.stdout,x.stderr,flush=True);assert x.returncode==0
