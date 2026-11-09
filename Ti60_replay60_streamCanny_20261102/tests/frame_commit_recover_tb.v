`timescale 1ns/1ps
// Focused check for frame_write_commit: an overflow must set fault, the fault must
// clear at the next frame begin, and pending commits must still be reported.
module frame_commit_recover_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,aw=0,br=0,fe=0,fb=0;
wire committed,fault;wire [31:0] caddr;
frame_write_commit #(.ADDR_WIDTH(32)) dut(.clk(clk),.rst_n(rst),
 .aw_accept(aw),.b_accept(br),.frame_data_end(fe),.frame_begin(fb),
 .frame_addr(32'h1000),.committed(committed),.committed_addr(caddr),.fault(fault));
integer i,pushes=0,pops=0;
always @(posedge clk)if(committed)pops=pops+1;
task tick;input integer n;begin repeat(n)@(posedge clk);#1;end endtask
task cycle;begin @(negedge clk);end endtask
initial begin
 tick(3);rst=1;tick(3);
 // Four frames queue up without any B response.
 for(i=0;i<4;i=i+1)begin
  @(negedge clk);aw=1;fe=1;tick(1);@(negedge clk);aw=0;fe=0;tick(2);
 end
 if(fault)$fatal(1,"fault asserted without overflow");
 // Fifth frame cannot be queued: fault must assert.
 @(negedge clk);fe=1;tick(1);@(negedge clk);fe=0;tick(2);
 if(!fault)$fatal(1,"overflow did not raise fault");
 // A new camera frame boundary must clear the fault again.
 @(negedge clk);fb=1;tick(1);@(negedge clk);fb=0;tick(2);
 if(fault)$fatal(1,"fault not cleared by frame_begin");
 // Drain the four queued commits.
 for(i=0;i<4;i=i+1)begin
  @(negedge clk);br=1;tick(1);@(negedge clk);br=0;tick(3);
 end
 if(pops!=4)$fatal(1,"expected 4 commits, got %0d",pops);
 if(fault)$fatal(1,"fault reappeared while draining");
 $display("PASS: commit tracker raises fault on overflow, clears it at frame begin, keeps 4 pending commits");
 $finish;
end
initial begin #200000;$fatal(1,"timeout");end
endmodule
