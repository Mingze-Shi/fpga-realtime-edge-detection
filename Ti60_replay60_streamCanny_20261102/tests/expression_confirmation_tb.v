`timescale 1ns/1ps
module expression_confirmation_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,en=1,completion=0,accept=0;reg[2:0]candidate=0;
wire matched,valid,busy;wire[2:0]cls;
taffy_expression_cnn_match dut(.clk(clk),.rst_n(rst),.enable(en),.de(1'b0),.vs(1'b0),.x(12'd0),.y(12'd0),.gray(8'd0),
 .matched(matched),.result_valid(valid),.busy(busy),.class_id(cls),.logit0(),.logit1(),.logit2(),.logit3(),.logit4());
task result;input [2:0]id;input ok;input[2:0]expected;
begin
 @(negedge clk);candidate=id;accept=ok;completion=1;
 @(negedge clk);completion=0;
 if(cls!==expected || matched!==(expected!=0))$fatal(1,"confirmation id %0d expected %0d got %0d",id,expected,cls);
end endtask
initial begin
 force dut.done=completion;force dut.target=accept;force dut.core_class=candidate;
 repeat(4)@(negedge clk);rst=1;
 result(1,1,0);result(1,1,0);result(1,1,1);
 result(2,1,0);result(3,1,0);result(2,1,0);result(2,1,0);result(2,1,2);
 result(2,0,0);result(4,1,0);result(4,1,0);result(4,1,4);result(0,0,0);
 @(negedge clk);en=0;repeat(3)@(negedge clk);if(valid||matched||cls!=0)$fatal(1,"disable failed");
 $display("PASS: expression confirmation requires three consecutive SAME classes, rejects immediately, clears on mode exit");$finish;
end
endmodule
