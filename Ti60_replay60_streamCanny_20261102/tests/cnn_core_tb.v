`timescale 1ns/1ps
module cnn_core_tb;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,sample_valid=0,start=0;
reg [9:0] sample_index=0;reg [7:0] sample_data=0;
wire busy,done,target,valid_result,fv;wire [1:0] fl;wire[9:0] fa;wire[7:0] fd;
wire signed [31:0] l0,l1;
taffy_cnn_core #(.NORMALIZE(0)) dut(.clk(clk),.rst_n(rst_n),
.sample_valid(sample_valid),.sample_index(sample_index),.sample_data(sample_data),
.start(start),.input_min(8'd0),.input_max(8'd255),.busy(busy),.done(done),.target(target),.valid_result(valid_result),
.logit0(l0),.logit1(l1),.feature_valid(fv),.feature_layer(fl),.feature_address(fa),.feature_value(fd));
reg[7:0] image[0:1023],p1[0:1023],p2[0:511],p3[0:511],av[0:7];
reg[31:0] expected[0:63];reg[1023:0] path;
integer n,i,cycles,total_cycles=0,checks=0,case_checks;
always @(posedge clk)if(fv)begin
 if(fd!==(fl==0 ? p1[fa]:fl==1 ? p2[fa]:p3[fa]))$fatal(1,"case %0d layer %0d address %0d got %0d",n,fl,fa,fd);
 checks=checks+1;case_checks=case_checks+1;
end
initial begin
$readmemh("tests/cnn_vectors/expected_logits.hex",expected);
repeat(4)@(negedge clk);rst_n=1;
for(n=0;n<32;n=n+1)begin
 $sformat(path,"tests/cnn_vectors/%02d_input.hex",n);$readmemh(path,image);
 $sformat(path,"tests/cnn_vectors/%02d_pool1.hex",n);$readmemh(path,p1);
 $sformat(path,"tests/cnn_vectors/%02d_pool2.hex",n);$readmemh(path,p2);
 $sformat(path,"tests/cnn_vectors/%02d_conv3.hex",n);$readmemh(path,p3);
 $sformat(path,"tests/cnn_vectors/%02d_avg.hex",n);$readmemh(path,av);
 case_checks=0;
 for(i=0;i<1024;i=i+1)begin @(negedge clk);sample_valid=1;sample_index=i;sample_data=image[i];end
 @(negedge clk);sample_valid=0;start=1;@(negedge clk);start=0;cycles=0;
 while(!done && cycles<1000000)begin @(negedge clk);cycles=cycles+1;end
 if(!done)$fatal(1,"CNN timeout");
 if(l0!==expected[2*n] || l1!==expected[2*n+1])$fatal(1,"logits case %0d got %0d %0d expected %0d %0d",n,l0,l1,$signed(expected[2*n]),$signed(expected[2*n+1]));
 if(target!==(l1>l0)||!valid_result || case_checks!=2048)$fatal(1,"status/feature count");
 for(i=0;i<8;i=i+1)if(dut.average[i]!==av[i])$fatal(1,"GAP mismatch");
 total_cycles=total_cycles+cycles;
 $display("CNN case %0d passed: logits=%0d,%0d cycles=%0d",n,l0,l1,cycles);
 @(negedge clk);
end
$display("PASS: CNN int8 32 cases, %0d feature comparisons, all GAP values and logits; cycles/case=%0d",checks,total_cycles/32);
$finish;
end
endmodule
