`timescale 1ns/1ps
module capture_tmds_tb;
    reg clk=0, rst=1, de=0;
    reg [7:0] data=0;
    reg [1:0] control=0;
    wire [9:0] symbol;
    reg [7:0] decoded, q;
    integer i,j,k;
    capture_tmds_channel dut(clk,rst,de,data,control,symbol);
    always #5 clk=~clk;
    initial begin
        @(negedge clk); rst=0;
        for(i=0;i<4;i=i+1) begin
            control=i; @(posedge clk); #1;
            case(i)
                0: if(symbol!==10'b1101010100) $fatal(1,"control 0");
                1: if(symbol!==10'b0010101011) $fatal(1,"control 1");
                2: if(symbol!==10'b0101010100) $fatal(1,"control 2");
                3: if(symbol!==10'b1010101011) $fatal(1,"control 3");
            endcase
            @(negedge clk);
        end
        de=1;
        for(k=0;k<16;k=k+1) begin
            for(i=0;i<256;i=i+1) begin
                data=(i*73+k); @(posedge clk); #1;
                q=symbol[9] ? ~symbol[7:0] : symbol[7:0];
                decoded[0]=q[0];
                for(j=1;j<8;j=j+1)
                    decoded[j]=symbol[8] ? (q[j]^q[j-1]) : ~(q[j]^q[j-1]);
                if(decoded!==data) $fatal(1,"TMDS round trip");
                if($signed(dut.disparity)>8 || $signed(dut.disparity)<-8)
                    $fatal(1,"TMDS running disparity");
                @(negedge clk);
            end
        end
        $display("PASS: controls and 4096 pixel round trips"); $finish;
    end
endmodule
