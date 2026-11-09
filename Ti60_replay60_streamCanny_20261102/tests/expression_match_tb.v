`timescale 1ns/1ps
module expression_match_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,stable_en=0,de=0,vs=0;
    reg [11:0] x=0,y=0;
    reg [7:0] gray=0,pixels[0:70655];
    reg [2:0] expected[0:68];reg [15:0] scores[0:137];
    wire matched,valid,busy,sm,sv,sb;
    wire [2:0] cls,sc;
    wire [15:0] best,second,sbest,ssecond;
    taffy_expression_match #(.ROI_X(16),.ROI_Y(8),.SAMPLE_STEP_X(2),.SAMPLE_STEP_Y(1),.CONFIRM_FRAMES(1)) dut(
        .clk(clk),.rst_n(rst),.enable(en),.de(de),.vs(vs),.x(x),.y(y),.gray(gray),
        .matched(matched),.result_valid(valid),.class_id(cls),.best_error(best),.second_error(second),.busy(busy));
    taffy_expression_match #(.ROI_X(16),.ROI_Y(8),.SAMPLE_STEP_X(2),.SAMPLE_STEP_Y(1)) stable(
        .clk(clk),.rst_n(rst),.enable(stable_en),.de(de),.vs(vs),.x(x),.y(y),.gray(gray),
        .matched(sm),.result_valid(sv),.class_id(sc),.best_error(sbest),.second_error(ssecond),.busy(sb));
    task ticks;input integer n;begin repeat(n) begin @(posedge clk);#2;end end endtask
    task boundary;begin @(negedge clk);de=0;vs=1;ticks(3);@(negedge clk);vs=0;ticks(3);end endtask
    task frame;input integer idx;input integer malformed;integer i;
        begin
            for(i=0;i<1024;i=i+1) begin
                @(negedge clk);de=1;x=17+2*(i%32);y=8+i/32;gray=pixels[idx*1024+i];
                if(malformed==1 && i==123) de=0;
                if(malformed==2 && i==123) x=x+2;
                ticks(1);
            end
            @(negedge clk);de=0;boundary;
            if(malformed==0) begin
                if(!busy) $fatal(1,"matcher did not start");
                wait(!busy);ticks(2);
            end else ticks(8);
        end
    endtask
    integer c;
    initial begin
        $readmemh("test_output/expression_samples.hex",pixels);
        $readmemh("test_output/expression_expected.hex",expected);
        $readmemh("test_output/expression_expected_scores.hex",scores);
        ticks(4);@(negedge clk);rst=1;boundary;
        for(c=0;c<69;c=c+1) begin
            frame(c,0);
            if(!valid || cls!==expected[c] || matched!==(expected[c]!=0))
                $fatal(1,"case=%0d class got=%0d expected=%0d",c,cls,expected[c]);
            if(best!==scores[2*c] || second!==scores[2*c+1])
                $fatal(1,"integer score mismatch case=%0d got=%0d/%0d expected=%0d/%0d",c,best,second,scores[2*c],scores[2*c+1]);
        end
        $display("PASS: expression integer RTL equals Python on 69 cases and all best/second scores.");
        @(negedge clk);stable_en=1;
        frame(0,0);if(sm || sc) $fatal(1,"accepted first frame");
        frame(15,0);if(sm || sc) $fatal(1,"different classes incorrectly accumulated");
        frame(15,0);if(sm || sc) $fatal(1,"accepted second same-class frame");
        frame(15,0);if(!sm || sc!=2) $fatal(1,"three-frame class 2 missing");
        frame(0,0);if(sm || sc) $fatal(1,"old class retained after class change");
        frame(60,0);if(sm || sc) $fatal(1,"blank did not revoke");
        repeat(3) frame(0,0);if(!sm || sc!=1) $fatal(1,"reacquire failed");
        frame(0,1);if(valid || matched || sv || sm) $fatal(1,"missing sample accepted");
        frame(0,2);if(valid || matched || sv || sm) $fatal(1,"bad order accepted");
        // Abort a running scan and ensure no stale completion can later appear.
        for(c=0;c<1024;c=c+1) begin
            @(negedge clk);de=1;x=17+2*(c%32);y=8+c/32;gray=pixels[c];ticks(1);
        end
        @(negedge clk);de=0;boundary;ticks(50);
        @(negedge clk);en=0;stable_en=0;ticks(8);
        if(busy || valid || matched || cls || sb || sv || sm || sc) $fatal(1,"disable did not clear");
        @(negedge clk);en=1;stable_en=1;boundary;
        frame(0,0);if(sm) $fatal(1,"disable retained streak");
        @(negedge clk);rst=0;ticks(4);
        if(valid || matched || cls || sv || sm || sc) $fatal(1,"reset retained result");
        $display("PASS: expression same-class debounce, class change, unknown, malformed samples, busy abort, disable and reset.");
        $finish;
    end
    initial begin #300000000;$fatal(1,"expression timeout");end
endmodule
