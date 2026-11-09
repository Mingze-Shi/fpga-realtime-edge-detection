`timescale 1ns/1ps
module expression_decision_tb;
reg clk=0;always #5 clk=~clk;reg rst=0,start=0;wire busy,done;reg signed [31:0] a,b,c,d,e;wire[2:0]cls;wire accepted,pp,mp;
expression_cnn_decision_seq dut(clk,rst,start,a,b,c,d,e,busy,done,cls,accepted,pp,mp);
reg[31:0]scores[0:4609];reg[7:0]status[0:921];integer i;
initial begin
 $readmemh("tests/expression_cnn_vectors/decision_logits.hex",scores);
 $readmemh("tests/expression_cnn_vectors/decision_expected.hex",status);
 repeat(3)@(negedge clk);rst=1;
 for(i=0;i<922;i=i+1)begin
 a=scores[5*i];b=scores[5*i+1];c=scores[5*i+2];d=scores[5*i+3];e=scores[5*i+4];
 @(negedge clk);start=1;@(negedge clk);start=0;wait(done);@(negedge clk);
 if({mp,pp,accepted,cls}!==status[i][5:0])$fatal(1,"decision mismatch %0d",i);
 end
 $display("PASS: expression decision 922 cases: low score, ties, near ties, class zero, signed extremes, conservative probability and margin");$finish;
end
endmodule
