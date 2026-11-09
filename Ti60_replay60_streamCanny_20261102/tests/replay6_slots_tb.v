`timescale 1ns/1ps
module replay6_slots_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,boundary=0,freeze=0,replay=0,begin_w=0,done=0,fault=0;
reg [2:0] sel=0;reg[3:0]committed=0,reading=9;
wire ready,frozen,locked,read_ready;wire[3:0]ws,rs,ls;wire[2:0]ack;wire[31:0]wa,ra,la;
replay6_slots #(.STRIDE(4608)) dut(clk,rst,boundary,freeze,replay,1'b0,sel,
 begin_w,done,fault,committed,reading,ready,ws,rs,ls,frozen,locked,ack,wa,ra,la,read_ready);
integer tags[0:9],saved[0:5],n,k,serial=0,slot,old,checked=0;
task tick;input integer count;integer j;begin repeat(count)begin @(posedge clk);#1;end end endtask
task rb;begin @(negedge clk);boundary=1;tick(1);@(negedge clk);boundary=0;reading=rs;tick(1);end endtask
task capture;input integer tag;begin
 if(!ready)$fatal(1,"no free slot");
 slot=wa/4608;
 if(slot==rs || slot==reading)$fatal(1,"reader overwritten");
 for(k=0;k<dut.count;k=k+1)if(slot==dut.history[k])$fatal(1,"history overwritten");
 @(negedge clk);begin_w=1;tick(1);@(negedge clk);begin_w=0;
 tick(7);if(ws!=slot || ready)$fatal(1,"write ownership lost before B");
 tags[slot]=tag;committed=slot;done=1;tick(1);@(negedge clk);done=0;tick(2);
end endtask
initial begin
 for(n=0;n<10;n=n+1)tags[n]=-1;
 tick(3);rst=1;tick(3);
 // An early single-freeze request must not acknowledge uninitialized DDR.
 freeze=1;tick(10);if(frozen)$fatal(1,"uninitialized single freeze acknowledged");
 capture(99);rb();if(!frozen || tags[rs]!=99)$fatal(1,"first valid frame not frozen");
 // Reset and enter replay before history exists: collect all six commits.
 rst=0;freeze=0;tick(3);rst=1;tick(3);
 freeze=1;replay=1;tick(10);
 for(n=0;n<6;n=n+1)capture(n);
 tick(8);if(locked)$fatal(1,"ack before descriptor boundary");rb();
 if(!locked || ready)$fatal(1,"early freeze did not lock six");
 for(n=0;n<6;n=n+1)begin
  sel=n;tick(12);old=rs;tick(5);if(rs!=old)$fatal(1,"midframe switch");rb();
  if(ack!=n || tags[rs]!=5-n)$fatal(1,"wrong frozen order %0d",n);checked=checked+1;
 end
 replay=0;freeze=0;tick(8);rb();tick(4);
 for(n=6;n<306;n=n+1)begin
  capture(n);if(n%3==0)rb();
  if(n%19==0)begin
   freeze=1;replay=1;sel=0;tick(12);rb();
   for(k=0;k<6;k=k+1)saved[k]=n-k;
   for(k=0;k<18;k=k+1)begin sel=k%6;tick(12);rb();
    if(ready || tags[rs]!=saved[k%6] || ack!=k%6)$fatal(1,"unstable six-frame set");checked=checked+1;
   end
   replay=0;freeze=0;tick(8);rb();tick(4);
  end
 end
 freeze=1;tick(10);old=rs;
 for(n=306;n<320;n=n+1)begin capture(n);rb();if(rs!=old)$fatal(1,"single freeze moved");end
 fault=1;tick(5);if(ready || locked)$fatal(1,"fault not closed");
 $display("PASS: six-frame slots: 321 captures, %0d selections, early freeze, delayed completion, protected reader and fault",checked);$finish;
end
initial begin #2000000;$fatal(1,"timeout");end
endmodule
