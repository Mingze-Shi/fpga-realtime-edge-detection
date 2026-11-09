// Ten external DDR slots: six committed history frames plus protected live IO.
// Only metadata is kept here. The existing DDR IP and RAW video path are reused.
module replay6_slots #(parameter STRIDE=4147712,START_ADDR=0,HISTORY_FRAMES=6,SELECT_BITS=$clog2(HISTORY_FRAMES),SLOT_COUNT=HISTORY_FRAMES+4,SLOT_BITS=$clog2(SLOT_COUNT))(
 input clk,rst_n,read_boundary,freeze_request,replay_request,
 input delay_mode,
 input [SELECT_BITS-1:0] selection,
 input write_begin,write_done,fault,input [SLOT_BITS-1:0] committed_slot,reading_slot,
 output write_ready,output reg [SLOT_BITS-1:0] write_slot,read_slot,
 output reg [SLOT_BITS-1:0] live_slot,
 output frozen,output replay_ready,output reg [SELECT_BITS-1:0] selection_ack,
 output [31:0] write_address,read_address,
 live_address,
 output read_ready);
 reg [SLOT_BITS-1:0] history[0:HISTORY_FRAMES-1],saved[0:HISTORY_FRAMES-1];
 reg [SELECT_BITS:0] count;
 reg writing,locked,selected_valid,read_has_frame;
 (* async_reg="true" *) reg fm,fs,rm,rs;
 (* async_reg="true" *) reg [SELECT_BITS-1:0] sm,ss;
 reg [SELECT_BITS-1:0] stable_select,last_select;
 reg [2:0] stable_count;
 reg [SLOT_COUNT-1:0] protect;
 reg found;reg[SLOT_BITS-1:0] candidate;
 integer i,j;
 always @* begin
   protect=0;
   protect[read_slot]=1;protect[reading_slot]=1;protect[live_slot]=1;
   if(writing)protect[write_slot]=1;
   for(integer k=0;k<HISTORY_FRAMES;k=k+1)begin
     if(k<count)protect[history[k]]=1;
     if(locked)protect[saved[k]]=1;
   end
   found=0;candidate=0;
   for(integer k=SLOT_COUNT-1;k>=0;k=k-1)if(!protect[k])begin candidate=k;found=1;end
 end
 assign write_ready=!writing && found && !fault && !locked && (!rs || count<HISTORY_FRAMES);
 // Candidate is combinational while idle; write_begin latches ownership before
 // any AW. During a frame its address never changes, including delayed B.
 assign write_address=START_ADDR+(writing ? write_slot:candidate)*STRIDE;
 assign read_address=START_ADDR+read_slot*STRIDE;
 assign live_address=START_ADDR+live_slot*STRIDE;
 assign read_ready=read_has_frame && !fault;
 assign frozen=(delay_mode ? 1'b1 : fs) && read_has_frame;
 assign replay_ready=delay_mode ? (count!=0 && !fault) : (locked && selected_valid && !fault);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
  fm<=0;fs<=0;rm<=0;rs<=0;sm<=0;ss<=0;last_select<=0;stable_select<=0;stable_count<=0;
  count<=0;writing<=0;locked<=0;selected_valid<=0;read_has_frame<=0;write_slot<=0;read_slot<=SLOT_COUNT-1;selection_ack<=0;
live_slot<=SLOT_COUNT-1;
  for(i=0;i<HISTORY_FRAMES;i=i+1)begin history[i]<=0;saved[i]<=0;end
 end else begin
  fm<=freeze_request;fs<=fm;rm<=replay_request;rs<=rm;sm<=selection;ss<=sm;
  if(ss!=last_select)begin last_select<=ss;stable_count<=0;end
  else if(stable_count<4)stable_count<=stable_count+1'b1;
  else if(ss<HISTORY_FRAMES)stable_select<=ss;
  if(write_begin && write_ready)begin writing<=1;write_slot<=candidate;end
  if(write_done && writing && committed_slot==write_slot && !fault)begin
   writing<=0;
   for(j=HISTORY_FRAMES-1;j>0;j=j-1)history[j]<=history[j-1];
   history[0]<=write_slot;if(count<HISTORY_FRAMES)count<=count+1'b1;
  end
  // A lost commit must not pin slot ownership forever: release it so the next
  // frame can start once the commit tracker clears its fault.
  if(fault)writing<=0;
  // Lock the six latest fully committed frames. An in-flight frame completes
  // first; no partially written frame can enter the frozen set.
  if(!delay_mode && rs && fs && !locked && !writing && count==HISTORY_FRAMES && !fault)begin
   for(i=0;i<HISTORY_FRAMES;i=i+1)saved[i]<=history[i];
   locked<=1;selected_valid<=0;selection_ack<=0;
  end
  if(read_boundary)begin
  if(count!=0 && !fault)live_slot<=history[0];
   if(delay_mode)begin
   if(count!=0 && stable_select<count)begin read_slot<=history[stable_select];read_has_frame<=1;end
   locked<=0;selected_valid<=0;selection_ack<=stable_select;
  end else if(locked && rs && !fault)begin read_slot<=saved[stable_select];selection_ack<=stable_select;selected_valid<=1;read_has_frame<=1;end
   else if(!rs)begin
    if(locked)begin locked<=0;selected_valid<=0;end
    if((!fs || !read_has_frame) && count!=0 && !fault)begin read_slot<=history[0];read_has_frame<=1;end
   end
  end
 end
 end
endmodule
