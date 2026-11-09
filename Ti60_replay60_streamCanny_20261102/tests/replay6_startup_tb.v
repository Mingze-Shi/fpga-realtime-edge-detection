`timescale 1ns/1ps
module replay6_startup_tb #(parameter INPUT_BEATS=1024);
reg clk=0;always #5 clk=~clk;
reg rst=0,vs=1,de=0;reg[31:0]pixel=0;
wire awvalid,wvalid,wlast,br;wire[127:0]wd;reg bv=0;
integer starts=0,commits=0,tag=0,k,words=0,totalwords=0;
frame_buffer #(.I_VID_WIDTH(32),.O_VID_WIDTH(16),.AXI_DATA_WIDTH(128),.AXI_ADDR_WIDTH(32),
 .FB_NUM(10),.REPLAY_ENABLE(1),.REPLAY_FRAMES(6),.MAX_VID_WIDTH(32),.MAX_VID_HIGHT(32),
 .O_FRAME_WIDTH(32),.O_FRAME_HEIGHT(32),.START_ADDR(0),.BURST_LEN(127)) dut(
 .axi_clk(clk),.rst_n(rst),.i_clk(clk),.i_vs(vs),.i_de(de),.vin(pixel),.o_clk(clk),
 .freeze_request(1'b0),.replay_request(1'b0),.split_request(1'b0),.replay_select(3'd0),.fifo_rd_period(1'b0),.m_axis_tready(1'b1),
 .awvalid(awvalid),.awready(1'b1),.wvalid(wvalid),.wready(1'b1),.wlast(wlast),.wdata(wd),
 .bid(6'd0),.bvalid(bv),.bready(br),.arready(1'b1),.rid(6'd0),.rdata(128'd0),.rlast(1'b0),.rvalid(1'b0),.rresp(2'd0));
always @(posedge clk)begin
 bv<=wvalid&&wlast;
 if(rst)begin
  if(dut.u_ddr_buffer.slot_begin)begin
   if(!dut.frame_stable || dut.ddr_frame_len!=INPUT_BEATS/4)$fatal(1,"startup/size gate bypassed");
   starts=starts+1;words=0;
  end
  if(wvalid)begin
   if(wd!=={4{pixel}})$fatal(1,"camera packing / previous frame data leaked");
   words=words+1;totalwords=totalwords+1;
  end
  if(dut.u_ddr_buffer.frame_committed)begin
   if(words!=INPUT_BEATS/4)$fatal(1,"startup partial commit");commits=commits+1;
  end
  if(dut.u_ddr_buffer.commit_fault)$fatal(1,"startup caused sticky write fault");
 end
end
task tick;input integer n;begin repeat(n)begin @(posedge clk);#2;end end endtask
initial begin
 tick(6);rst=1;tick(20);
 // Startup includes empty VS periods before the first valid camera image.
 repeat(3)begin @(negedge clk);vs=0;tick(20);@(negedge clk);vs=1;tick(20);end
 if(starts!=0)$fatal(1,"zero-size camera frame accepted");
 for(tag=1;tag<=12;tag=tag+1)begin
  @(negedge clk);pixel=tag;vs=0;tick(10);
  for(k=0;k<INPUT_BEATS;k=k+1)begin @(negedge clk);de=1;end
  @(negedge clk);de=0;tick(180);@(negedge clk);vs=1;tick(64);
 end
 tick(100);if(commits<6 || starts!=commits)$fatal(1,"startup failed to accumulate six full frames");
 if(dut.u_ddr_buffer.FRAME_STRIDE!=4608)$fatal(1,"frame dimensions not forwarded");
 $display("PASS: camera-to-DDR wrapper startup: empty VS rejected, dimensions forwarded, %0d full frames and %0d packed words committed",commits,totalwords);$finish;
end
initial begin #1000000;$fatal(1,"startup timeout");end
endmodule
