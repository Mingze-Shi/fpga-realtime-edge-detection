from pathlib import Path
r=Path.cwd()
p=r/'rtl/replay6_slots.v';s=p.read_text(encoding="latin1");s=s.replace('START_ADDR=0)(', 'START_ADDR=0,HISTORY_FRAMES=6,SELECT_BITS=$clog2(HISTORY_FRAMES),SLOT_COUNT=HISTORY_FRAMES+4,SLOT_BITS=$clog2(SLOT_COUNT))(')
s=s.replace('[2:0] selection','[SELECT_BITS-1:0] selection').replace('[2:0] sm,ss','[SELECT_BITS-1:0] sm,ss').replace('[2:0] stable_select,last_select','[SELECT_BITS-1:0] stable_select,last_select').replace('[2:0] count','[SELECT_BITS:0] count')
s=s.replace('[3:0]','[SLOT_BITS-1:0]').replace('[0:5]','[0:HISTORY_FRAMES-1]').replace('[9:0] protect','[SLOT_COUNT-1:0] protect').replace('k<6','k<HISTORY_FRAMES').replace('k=9','k=SLOT_COUNT-1').replace('count<6','count<HISTORY_FRAMES').replace('ss<6','ss<HISTORY_FRAMES').replace('i<6','i<HISTORY_FRAMES').replace('j=5','j=HISTORY_FRAMES-1').replace('count==6','count==HISTORY_FRAMES').replace('read_slot<=9','read_slot<=SLOT_COUNT-1').replace('live_slot<=9','live_slot<=SLOT_COUNT-1')
s=s.replace('protect[read_slot]=1;protect[reading_slot]=1;','protect[read_slot]=1;protect[reading_slot]=1;protect[live_slot]=1;')
s=s.replace('if(count!=0)begin read_slot<=history[stable_select];','if(count!=0 && stable_select<count)begin read_slot<=history[stable_select];')
p.write_text(s,encoding="latin1")
for name in ['rtl/frame_buffer_V4/ddr_buffer.v','rtl/frame_buffer_V4/frame_buffer.v']:
 p=r/name;s=p.read_text(encoding="latin1");s=s.replace('FB_NUM==10','FB_NUM>=10').replace('FB_NUM!=10','FB_NUM<10')
 if name.endswith('ddr_buffer.v'):
  s=s.replace('function [3:0] slot_of;','localparam SLOT_BITS=$clog2(FB_NUM);\nfunction [SLOT_BITS-1:0] slot_of;').replace('n<10','n<FB_NUM').replace('wire [3:0] ws,rs','wire [SLOT_BITS-1:0] ws,rs').replace('.START_ADDR(START_ADDR)) u_slots(','.START_ADDR(START_ADDR),.HISTORY_FRAMES(REPLAY_FRAMES)) u_slots(')
 p.write_text(s,encoding="latin1")
p=r/'rtl/ti60f225_oob_top.v';s=p.read_text(encoding="latin1").replace('wire [2:0] replay_select,replay_selection_ack','wire [5:0] replay_select,replay_selection_ack').replace('(10),','(64),').replace('.REPLAY_FRAMES(6)','.REPLAY_FRAMES(60)');p.write_text(s,encoding="latin1")
p=r/'rtl/sc431_sobel_video.v';s=p.read_text(encoding="latin1").replace('REPLAY_FRAMES==6 ? 8:2','REPLAY_FRAMES>=6 ? 8:2');p.write_text(s,encoding="latin1")

