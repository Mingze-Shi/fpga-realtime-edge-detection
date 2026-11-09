`timescale 1ns/1ps
module replay6_control_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,fs=0,toggle=0,step=0,prev=0,fa=0,ra=0,mv=1;
reg[1:0]mode=0;reg[2:0]ack=0;
wire freeze,replay,reset_work,visible;wire[2:0]sel;
canny_snapshot_control #(.REPLAY_FRAMES(6)) dut(clk,rst,fs,mode,toggle,step,prev,fa,ra,mv,ack,freeze,replay,sel,reset_work,visible);
task tick;input integer n;begin repeat(n)begin @(posedge clk);#1;end end endtask
task frame;begin @(negedge clk);fs=1;tick(1);@(negedge clk);fs=0;tick(1);end endtask
task key;input p;begin @(negedge clk);prev=p;step=1;tick(1);@(negedge clk);step=0;tick(1);end endtask
integer n,expected;
initial begin tick(3);rst=1;tick(3);mode=3;tick(3);
 if(!freeze || !replay)$fatal(1,"mode3 not requesting lock");
 key(1);if(sel!=0)$fatal(1,"accepted key before lock ack");
 fa=1;ra=1;tick(5);repeat(4)frame();if(!visible)$fatal(1,"did not settle");
 for(n=0;n<14;n=n+1)begin
  expected=(sel+1)%6;key(1);if(sel!=expected || !reset_work || visible)$fatal(1,"previous/reset");
  key(1);if(sel!=expected)$fatal(1,"unacked command overwritten");
  ack=sel;tick(5);repeat(4)frame();if(!visible)$fatal(1,"previous did not settle");
 end
 for(n=0;n<14;n=n+1)begin
  expected=sel==0 ? 5:sel-1;key(0);if(sel!=expected)$fatal(1,"next wrap");
  ack=sel;tick(5);repeat(4)frame();
 end
 toggle=1;tick(3);if(freeze || replay || visible)$fatal(1,"refresh did not unlock");
 fa=0;ra=0;tick(5);repeat(2)frame();if(!freeze || !replay)$fatal(1,"refresh no relock");
 mode=1;tick(4);if(replay)$fatal(1,"live retains replay");
 $display("PASS: six-frame control: bidirectional wrap, pending-ack key rejection, map invalidation and refresh");$finish;
end
endmodule
