`timescale 1ns/1ps
// Behavioral synchronous FIFO and AXI memory replace only device primitives.
// Actual DDR writer/reader, B commit tracker and six-slot manager are used.
module DC_FIFO #(parameter FIFO_MODE="Normal",DATA_WIDTH=128,FIFO_DEPTH=1024)(
 input Reset,WrClk,WrEn,input[DATA_WIDTH-1:0]WrData,
 output[$clog2(FIFO_DEPTH):0]WrDNum,output WrFull,
 input RdClk,RdEn,output[$clog2(FIFO_DEPTH):0]RdDNum,output RdEmpty,
 output reg[DATA_WIDTH-1:0]RdData);
 reg[DATA_WIDTH-1:0]mem[0:FIFO_DEPTH-1];integer wp=0,rp=0,count=0;
 assign WrDNum=count;assign RdDNum=count;assign WrFull=count==FIFO_DEPTH;assign RdEmpty=count==0;
 always @(posedge WrClk or posedge Reset)begin
  if(Reset)begin wp<=0;rp<=0;count<=0;RdData<=0;end
  else begin
   if(WrEn && !WrFull)begin mem[wp]<=WrData;wp<=(wp+1)%FIFO_DEPTH;end
   if(RdEn && !RdEmpty)begin RdData<=mem[rp];rp<=(rp+1)%FIFO_DEPTH;end
   case({WrEn&&!WrFull,RdEn&&!RdEmpty})2'b10:count<=count+1;2'b01:count<=count-1;endcase
  end
 end
endmodule
module replay6_ddr_tb #(parameter FULL=0,FRAME_WORDS=256,SIMPLE=0);
localparam WORDS=FULL ? 129600:FRAME_WORDS;
localparam SLOT_BYTES=FULL ? 4147712:4608;
localparam MEMORY_WORDS=SLOT_BYTES/16*10;
reg clk=0;always #5 clk=~clk;
reg rst=0,wrstart=0,rdstart=0,wrreset=1,rdreset=1,wren=0;
reg [31:0] read_length_override=WORDS;
reg freeze=0,replay=0;reg[2:0]select_frame=0;wire fa,ra;wire[2:0]ack;
reg[127:0]din=0;wire full,empty,rdvalid;wire[127:0]dout;
wire[31:0]awaddr,araddr;wire[7:0]awlen,arlen;wire awvalid,wvalid,wlast,bready,arvalid,rready;
wire[127:0]wdata;reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0,rlast=0;reg[127:0]rdata=0;
ddr_buffer #(.AXI_DATA_WIDTH(128),.AXI_ADDR_WIDTH(32),.FB_NUM(10),.REPLAY_ENABLE(1),.REPLAY_FRAMES(6),
 .MAX_VID_WIDTH(FULL ? 960:32),.MAX_VID_HIGHT(FULL ? 1080:32),.I_VID_WIDTH(32),.START_ADDR(0),.BURST_LEN(127)) dut(
 .axi_clk(clk),.axi_clk_rst_n(rst),.wr_clk_rst_n(rst),.rd_clk_rst_n(rst),
 .freeze_request(freeze),.replay_request(replay),.split_request(1'b0),.replay_select(select_frame),
 .freeze_active(fa),.replay_ready(ra),.replay_select_ack(ack),.wr_start(wrstart),.rd_start(rdstart),
 .wr_busrt_len(WORDS),.rd_burst_len(read_length_override),.wr_fifo_rst_p(wrreset),.wr_fifo_wrclk(clk),.wr_fifo_wren(wren),
 .wr_fifo_wrfull(full),.wr_fifo_wrdata(din),.rd_fifo_rdclk(clk),.rd_fifo_rst_p(rdreset),
 .rd_fifo_rdvalid(rdvalid),.rd_fifo_rddata(dout),.rd_fifo_rdempty(empty),.rd_fifo_rden(!empty),
 .awaddr(awaddr),.awlen(awlen),.awvalid(awvalid),.awready(awready),.wdata(wdata),.wlast(wlast),.wvalid(wvalid),.wready(wready),
 .bvalid(bvalid),.bready(bready),.bid(6'd0),.araddr(araddr),.arlen(arlen),.arvalid(arvalid),.arready(arready),
 .rdata(rdata),.rvalid(rvalid),.rready(rready),.rlast(rlast),.rid(6'd0),.rresp(2'd0));
reg[127:0]mem[0:MEMORY_WORDS-1];
integer b_due_queue[0:32767];integer b_head=0,b_tail=0;
integer cycle=0,waddr=0,wremain=0,raddr=0,rremain=0,bdue=0,delay_b=23;
integer words=0,rdwords=0,commits=0,begins=0,tag=0,n,i,start_commits,expected_base=0;
reg check_read=0,read_base_armed=0;
function[127:0]pattern;input integer t,j;begin pattern={32'hface0000+t,32'habc00000+j,32'h12340000+t,j[31:0]};end endfunction
always @(negedge clk)begin
 cycle=cycle+1;awready=(cycle%5!=0 && wremain==0);wready=cycle%7!=0;arready=rremain==0;
 bvalid=(b_head!=b_tail && cycle>=b_due_queue[b_head]);
 if(rremain!=0 && cycle%3!=0)begin rvalid=1;rdata=mem[raddr];rlast=rremain==1;end
 else begin rvalid=0;rlast=0;end
end
always @(posedge clk)if(rst)begin
 if(dut.slot_begin)begins=begins+1;
 if(dut.frame_committed)commits=commits+1;
 if(awvalid&&awready)begin
  if(wremain!=0)$fatal(1,"overlap AW");waddr=awaddr/16;wremain=awlen+1;
  if((awaddr%4096)+16*(awlen+1)>4096)$fatal(1,"cross 4K AW");
 end
 if(wvalid&&wready)begin
  if(wremain<=0)$fatal(1,"W without AW");
  if(wdata!==pattern(tag,words))$fatal(1,"write word corruption tag=%0d word=%0d got=%h",tag,words,wdata);
  if(wlast!=(wremain==1))$fatal(1,"WLAST count");
  mem[waddr]=wdata;waddr=waddr+1;wremain=wremain-1;words=words+1;
  if(wlast)begin b_due_queue[b_tail]=cycle+(words==WORDS ? delay_b:23);b_tail=(b_tail+1)%32768;end
 end
 if(bvalid&&bready)b_head=(b_head+1)%32768;
 if(arvalid && commits==0)$fatal(1,"DDR read before first committed frame");
 if(arvalid&&arready)begin
  raddr=araddr/16;rremain=arlen+1;
  if(check_read && !read_base_armed)begin expected_base=araddr/16;read_base_armed=1;end
  if((araddr%4096)+16*(arlen+1)>4096)$fatal(1,"cross 4K AR");
 end
 if(rvalid&&rready)begin raddr=raddr+1;rremain=rremain-1;end
end
always @(posedge clk)begin #1;if(check_read && rdvalid)begin
 if(dout!==mem[expected_base+rdwords])$fatal(1,"read pixel mismatch word=%0d",rdwords);
 rdwords=rdwords+1;
end end
task tick;input integer count;begin repeat(count)begin @(posedge clk);#2;end end endtask
task write_frame;input integer t;begin
 tag=t;words=0;start_commits=commits;
 @(negedge clk);wrreset=1;tick(3);@(negedge clk);wrreset=0;wrstart=1;tick(1);
 @(negedge clk);wrstart=0;tick(10);
 for(i=0;i<WORDS;i=i+1)begin @(negedge clk);din=pattern(t,i);wren=1;@(negedge clk);wren=0;end
 @(negedge clk);wren=0;
 wait(commits==start_commits+1);tick(5);
 if(words!=WORDS || dut.commit_fault)$fatal(1,"frame not complete");
end endtask
task read_frame;begin
 expected_base=dut.rd_start_addr/16;rdwords=0;read_base_armed=0;
 @(negedge clk);rdreset=1;tick(3);@(negedge clk);rdreset=0;check_read=1;rdstart=1;tick(1);
 @(negedge clk);rdstart=0;
 wait(rdwords==WORDS);tick(20);check_read=0;
 if(rdwords!=WORDS)$fatal(1,"extra read data");
end endtask
integer slot,base,before_begin,cs;
initial begin
 for(n=0;n<MEMORY_WORDS;n=n+1)mem[n]=0;
 tick(5);rst=1;wrreset=0;rdreset=0;tick(5);
 // Display can request repeatedly before the camera has any valid frames.
 repeat(3)begin @(negedge clk);rdstart=1;tick(2);@(negedge clk);rdstart=0;tick(25);end
 if(rdwords || dut.read_slot_ready)$fatal(1,"uninitialized image became readable");
 write_frame(99);

 if(FULL || SIMPLE)begin
  for(n=0;n<6;n=n+1)begin fork write_frame(n);read_frame(); join end
  freeze=1;replay=1;tick(20);read_length_override=0;read_frame();tick(10);
  for(n=0;n<6;n=n+1)begin
   select_frame=n;tick(15);read_frame();read_frame();
   base=dut.rd_start_addr/16;
   if(mem[base]!==pattern(5-n,0) || ack!=n)$fatal(1,"1080p six-frame content");
  end
  $display("PASS: packed geometry: six full frames stored; all six read pixel-exact through actual DDR RTL");$finish;
 end
 for(n=0;n<15;n=n+1)begin fork write_frame(n);read_frame(); join end
 // Delay final B beyond another VS: new frame must be skipped, old frame stays owned.
 delay_b=23;tag=15;words=0;cs=commits;
 @(negedge clk);wrreset=1;tick(3);@(negedge clk);wrreset=0;wrstart=1;tick(1);
 @(negedge clk);wrstart=0;tick(10);
 for(i=0;i<WORDS;i=i+1)begin @(negedge clk);din=pattern(15,i);wren=1;@(negedge clk);wren=0;end
 @(negedge clk);wren=0;
 wait(words>=128);delay_b=1000;wait(words==WORDS);tick(5);before_begin=begins;
 @(negedge clk);wrstart=1;tick(1);@(negedge clk);wrstart=0;tick(10);
 if(begins!=before_begin || commits!=cs)$fatal(1,"new frame accepted before B");
 freeze=1;replay=1;wait(commits==cs+1);tick(10);read_frame();tick(10);
 if(!ra)$fatal(1,"six freeze did not acknowledge");
 for(n=0;n<18;n=n+1)begin
  select_frame=n%6;tick(15);read_frame();read_frame();
  base=dut.rd_start_addr/16;
  if(mem[base]!==pattern(15-n%6,0) || ack!=n%6)$fatal(1,"six DDR content/order");
  if(dut.slot_ready)$fatal(1,"write enabled while frozen");
 end
 replay=0;freeze=0;tick(10);read_frame();tick(10);delay_b=23;
 write_frame(16);read_frame();
 // Camera overruns before a complete W frame: unpublished data must stay out
 // of the history. Recovery is an explicit reset, rather than a torn commit.
 cs=commits;before_begin=begins;
 @(negedge clk);wrreset=1;tick(3);@(negedge clk);wrreset=0;wrstart=1;tick(1);
 @(negedge clk);wrstart=0;tick(12);
 @(negedge clk);wrstart=1;tick(1);@(negedge clk);wrstart=0;tick(12);
 if(!dut.commit_fault || dut.slot_ready || commits!=cs || begins!=before_begin+1)
  $fatal(1,"partial-frame overrun not blocked");
 $display("PASS: actual DDR path: 18 complete frames, 18 six-frame selections, pixel-exact reads, AXI stalls, delayed B, resume and partial-frame rejection");$finish;
end
initial begin #1000000000;$fatal(1,"DDR timeout words=%0d rdwords=%0d commits=%0d state=%0d",words,rdwords,commits,dut.u_ddr_wr_buffer.state);end
endmodule
