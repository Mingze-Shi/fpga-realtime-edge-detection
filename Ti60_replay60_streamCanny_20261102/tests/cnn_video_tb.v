`timescale 1ns/1ps
module cnn_video_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,de=0,hs=0,vs=0,mode_n=1;reg[7:0]pixel=72;
wire od,oh,ov;wire[7:0]r,g,b,gray;
sc431_sobel_video #(.WIDTH(640),.HEIGHT(480),.CNN_ENABLE(1),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(10000000))dut(
.clk(clk),.rst_n(rst),.increase_n(1'b1),.decrease_n(1'b1),.mode_n(mode_n),
.freeze_ack(1'b0),.replay_ack(1'b0),.replay_selection_ack(1'b0),
.de_in(de),.hs_in(hs),.vs_in(vs),.red_in(pixel),.green_in(pixel),.blue_in(pixel),
.de_out(od),.hs_out(oh),.vs_out(ov),.gray_out(gray),.red_out(r),.green_out(g),.blue_out(b));
integer px,py,n,k,checks=0,panels=0,borders=0,input_x=0,input_y=0,warm=0;
reg[8:0]dp=0,hp=0,vp=0;integer xp[0:8],yp[0:8];
wire text_ink,text_panel;
cnn_status_text #(.WIDTH(640),.HEIGHT(480)) txt(.x(dut.x_output),.y(dut.y_output),
.matched(dut.cnn_recognition.shown_match),.valid_result(dut.cnn_recognition.shown_valid),.ink(text_ink),.panel(text_panel));
reg[23:0]expected;reg guide;
always @(posedge clk)if(rst)begin
for(k=8;k>0;k=k-1)begin xp[k]=xp[k-1];yp[k]=yp[k-1];end
xp[0]=input_x;yp[0]=input_y;dp={dp[7:0],de};hp={hp[7:0],hs};vp={vp[7:0],vs};warm=warm+1;#1;
if(warm>9 && {od,oh,ov}!=={dp[8],hp[8],vp[8]})$fatal(1,"CNN altered sync latency");
if(od && dut.display_mode_active==1)begin
 guide=xp[8]>=64 && xp[8]<576 && yp[8]>=112 && yp[8]<368 &&
 (xp[8]<68||xp[8]>=572||yp[8]<116||yp[8]>=364);
 expected=text_panel ? (text_ink ? 24'hffffff:24'h000000):guide ?
 (dut.cnn_recognition.shown_valid ? 24'hff4040:24'hffff00):24'h484848;
 if({r,g,b}!==expected)$fatal(1,"CNN OSD RGB mismatch at %0d,%0d",xp[8],yp[8]);
 checks=checks+1;if(text_panel)panels=panels+1;if(guide)borders=borders+1;
end
end
task ticks;input integer q;begin repeat(q)@(negedge clk);end endtask
task frame;begin
@(negedge clk);de=0;vs=1;ticks(4);vs=0;ticks(4);
for(py=0;py<480;py=py+1)begin
for(px=0;px<640;px=px+1)begin @(negedge clk);de=1;input_x=px;input_y=py;end
@(negedge clk);de=0;hs=1;ticks(3);hs=0;ticks(2);
end
ticks(30);
end endtask
initial begin
ticks(5);rst=1;ticks(10);mode_n=0;ticks(8);mode_n=1;ticks(8);
repeat(2)frame;
if(checks!=614400||panels==0||borders==0)$fatal(1,"CNN guide/status missing");
if(!dut.cnn_recognition.shown_valid)$fatal(1,"blank status not committed");
$display("PASS: CNN video 614400 RGB checks, guide and OSD, unchanged nine-clock sync latency");$finish;
end
endmodule
