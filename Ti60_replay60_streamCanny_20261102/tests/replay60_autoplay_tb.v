`timescale 1ns/1ps
module replay60_autoplay_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,fs=0,toggle=0,step=0,prev=0,fa=0,ra=0,mv=1;
reg [1:0] mode=0;reg [5:0] ack=0;
wire freeze,replay,reset_work,visible;wire [5:0] sel;
canny_snapshot_control #(.REPLAY_FRAMES(60),.AUTO_REPLAY(1),.PLAY_FRAMES(6),.RELEASE_FRAMES(8))
 dut(clk,rst,fs,mode,toggle,step,prev,fa,ra,mv,ack,freeze,replay,sel,reset_work,visible);
task tick;input integer n;begin repeat(n)begin @(posedge clk);#1;end end endtask
task frame;begin @(negedge clk);fs=1;tick(1);@(negedge clk);fs=0;tick(1);end endtask
task key;input p;begin @(negedge clk);prev=p;step=1;tick(1);@(negedge clk);step=0;tick(1);end endtask
task accept;begin ack=sel;fa=1;ra=1;tick(5);end endtask
integer n;
initial begin
 tick(3);rst=1;tick(3);mode=3;tick(3);
 if(sel!=59 || !freeze || !replay)$fatal(1,"must start from oldest");
 repeat(9)frame();key(0);
 if(sel!=59 || !reset_work || visible)$fatal(1,"advanced without lock");
 for(n=59;n>=0;n=n-1)begin
  if(sel!=n)$fatal(1,"wrong chronological selection");
  accept();repeat(5)frame();
  if(sel!=n || !reset_work || visible)$fatal(1,"early step or stale overlay");
  frame();
  if(n>0)begin
   if(sel!=n-1)$fatal(1,"missing automatic step");
   repeat(8)frame();key(1);
   if(sel!=n-1 || visible || !reset_work)$fatal(1,"overwrote pending selection");
  end
 end
 if(sel!=0 || !visible || reset_work)$fatal(1,"final map not enabled");
 repeat(15)frame();if(sel!=0)$fatal(1,"playback looped");
 key(1);if(sel!=1 || visible)$fatal(1,"manual previous");
 accept();repeat(4)frame();if(!visible)$fatal(1,"manual settle");
 toggle=1;tick(3);if(freeze || replay || visible)$fatal(1,"refresh did not release");
 fa=0;ra=0;tick(5);repeat(7)frame();if(freeze)$fatal(1,"short release");
 frame();if(!freeze || !replay || sel!=59)$fatal(1,"refresh did not restart");
 accept();key(0);if(sel!=58)$fatal(1,"manual interruption");
 accept();repeat(14)frame();if(sel!=58 || !visible)$fatal(1,"manual did not stop autoplay");
 mode=1;tick(3);if(replay || sel!=0)$fatal(1,"exit did not clear");
 mode=3;tick(3);if(sel!=59)$fatal(1,"reentry did not restart");
 mode=2;tick(3);ack=0;tick(5);repeat(4)frame();
 if(sel!=0 || !visible || replay)$fatal(1,"mode2 snapshot changed");
 $display("PASS: autoplay chronology, six-frame cadence, stalled ack, no stale overlay, final hold, manual interruption, refresh and mode isolation");
 $finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
