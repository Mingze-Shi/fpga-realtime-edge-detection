`timescale 1ns/1ps
module cnn_capture_tb;
reg clk=0;always #5 clk=~clk;
reg rst=0,en=1,de=0,vs=0;reg[11:0]x=0,y=0;reg[7:0]g=0;
wire matched,valid_result,busy;wire signed[31:0]l0,l1;
taffy_cnn_match #(.ROI_X(8),.ROI_Y(4))dut(.clk(clk),.rst_n(rst),.enable(en),.de(de),.vs(vs),.x(x),.y(y),.gray(g),
.matched(matched),.result_valid(valid_result),.busy(busy),.logit0(l0),.logit1(l1));
reg[7:0]raw[0:1023],normalized[0:1023];reg[31:0]gold[0:1];
integer px,py,i,n,c,blank=0,sample_checks=0,norm_checks=0,completed=0;
always @(posedge clk)begin
 if(dut.done)completed=completed+1;
 if(dut.sample_valid && !blank)begin
  if(dut.sample_data!==raw[dut.sample_index])$fatal(1,"area averaging error %0d",dut.sample_index);
  sample_checks=sample_checks+1;
 end
 if(dut.u_core.state==5 && !blank)begin
  if(dut.u_core.quotient[7:0]!==normalized[dut.u_core.norm_index])$fatal(1,"integer normalization mismatch %0d",dut.u_core.norm_index);
  norm_checks=norm_checks+1;
 end
end
task ticks;input integer k;begin repeat(k)@(negedge clk);end endtask
task vsync;begin @(negedge clk);de=0;vs=1;ticks(3);vs=0;ticks(3);end endtask
task frame;input integer rows;begin
 vsync;
 for(py=4;py<4+rows;py=py+1)begin
  for(px=8;px<520;px=px+1)begin
   @(negedge clk);de=1;x=px;y=py;
   g=blank ? 8'd77:raw[((py-4)/8)*32+(px-8)/16]+(((px^py)&1) ? 1:-1);
  end
  @(negedge clk);de=0;ticks(2);
 end
 @(negedge clk);de=0;ticks(6);
end endtask
task wait_result;input integer expected_count;begin
c=0;while(completed<expected_count && c<900000)begin @(negedge clk);c=c+1;end
if(completed!=expected_count)$fatal(1,"capture/core timeout");ticks(3);
end endtask
initial begin
$readmemh("tests/cnn_vectors/capture_raw.hex",raw);
$readmemh("tests/cnn_vectors/capture_normalized.hex",normalized);
$readmemh("tests/cnn_vectors/capture_logits.hex",gold);
ticks(5);rst=1;ticks(5);
frame(16);vsync;ticks(10);if(busy||valid_result)$fatal(1,"partial frame accepted");
sample_checks=0;
for(n=0;n<3;n=n+1)begin
 frame(256);vsync;wait_result(n+1);
 if(l0!==gold[0]||l1!==gold[1])$fatal(1,"capture logits mismatch %0d,%0d",l0,l1);
 if(matched!==(n==2))$fatal(1,"three-frame confirmation failed");
end
if(sample_checks!=3072||norm_checks!=3072)$fatal(1,"sample/normalization count");
blank=1;frame(256);wait_result(4);
if(matched||!valid_result||l1!=-1)$fatal(1,"flat-field quality gate failed");
@(negedge clk);en=0;ticks(5);if(busy||matched||valid_result)$fatal(1,"disable not cleared");
@(negedge clk);en=1;frame(256);@(negedge clk);rst=0;ticks(4);
if(busy||matched||valid_result)$fatal(1,"reset during inference failed");
$display("PASS: CNN capture area averaging, 3072 normalized pixels, incomplete frames, VS while busy, confirmation, flat field, disable and reset");
$finish;
end
endmodule
