from pathlib import Path
import subprocess,os,sys
r=Path.cwd();sys.path.insert(0,str(r/'tests'));from run_canny_tests import simulator
c,v=simulator();os.environ['PATH']=str(c.parent.parent/'mingw-w64/bin')+os.pathsep+os.environ['PATH']
s=(r/'tests/replay6_ddr_tb.v').read_text().replace('replay6_ddr_tb','replay60_ddr_tb').replace('SIMPLE=0','SIMPLE=1').replace('/16*10','/16*64').replace('reg[2:0]select_frame','reg[5:0]select_frame').replace('wire[2:0]ack','wire[5:0]ack').replace('.FB_NUM(10)','.FB_NUM(64)').replace('.REPLAY_FRAMES(6)','.REPLAY_FRAMES(60)').replace('n<6','n<60').replace('pattern(5-n','pattern(59-n').replace('six full','sixty full').replace('all six','all sixty');(r/'tests/replay60_ddr_tb.v').write_text(s)
src=['rtl/replay6_slots.v','rtl/frame_write_commit.v',*['rtl/frame_buffer_V4/'+x+'.v' for x in ['ddr_buffer','ddr_wr_buffer','ddr_rd_buffer']]]
p=r/'test_output/replay60_ddr.vvp';subprocess.run([str(c),'-g2012','-s','replay60_ddr_tb','-o',str(p),*src,'tests/replay60_ddr_tb.v'],check=True);x=subprocess.run([str(v),str(p)],capture_output=True,text=True);print(x.stdout,x.stderr);assert x.returncode==0
