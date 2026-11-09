`timescale 1ns/1ps
module threshold_video_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,up_n=1,down_n=1,de=0,hs=0,vs=0;
    reg [7:0] pixel=0;
    wire deo,hso,vso;wire [7:0] out;
    sc431_sobel_video #(.WIDTH(12),.DEBOUNCE_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.increase_n(up_n),.decrease_n(down_n),.mode_n(1'b1),
        .de_in(de),.hs_in(hs),.vs_in(vs),
        .red_in(pixel),.green_in(pixel),.blue_in(pixel),
        .de_out(deo),.hs_out(hso),.vs_out(vso),.gray_out(out)
    );
    task ticks;input integer n;integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk);#1;end end
    endtask
    task press_up;
        begin @(negedge clk);up_n=0;ticks(12);@(negedge clk);up_n=1;ticks(12);end
    endtask
    task press_down;
        begin @(negedge clk);down_n=0;ticks(12);@(negedge clk);down_n=1;ticks(12);end
    endtask
    integer white_count=0,right_count=0,left_gray_count=0;
    always @(posedge clk) begin
        #1;
        // Median has two warm-up rows; Sobel needs two further complete rows.
        // Only this interior has the analytically constant 128-strength ramp.
        if(rst_n && deo && dut.y_output>=4) begin
            if(dut.x_output>=6) begin
                right_count=right_count+1;
                if(out!==0 && out!==255) $fatal(1,"right output is not binary: %0d",out);
                if(out==255) white_count=white_count+1;
            end else if(out>0 && out<255) left_gray_count=left_gray_count+1;
        end
    end
    task frame;
        integer x,y;
        begin
            @(negedge clk);vs=1;de=0;ticks(3);@(negedge clk);vs=0;ticks(3);
            for(y=0;y<6;y=y+1) begin
                for(x=0;x<12;x=x+1) begin
                    @(negedge clk);de=1;pixel=x*16;
                end
                @(negedge clk);de=0;ticks(6);
            end
            ticks(12);
        end
    endtask
    initial begin
        ticks(6);@(negedge clk);rst_n=1;ticks(8);
        frame;
        if(right_count!=12 || white_count!=12 || left_gray_count==0)
            $fatal(1,"default frame incorrect: right=%0d white=%0d gray=%0d",right_count,white_count,left_gray_count);
        repeat(14) press_up;
        if(dut.threshold_requested!=144 || dut.threshold_active!=32)
            $fatal(1,"key update must wait for next frame");
        white_count=0;right_count=0;left_gray_count=0;frame;
        if(dut.threshold_active!=144 || right_count!=12 || white_count!=0 || left_gray_count==0)
            $fatal(1,"raising threshold did not suppress 128-strength edges");
        repeat(4) press_down;
        if(dut.threshold_active!=144) $fatal(1,"threshold changed outside frame boundary");
        white_count=0;right_count=0;frame;
        if(dut.threshold_active!=112 || white_count!=12) $fatal(1,"lowering threshold did not restore edges");
        @(negedge clk);rst_n=0;ticks(4);
        if(dut.threshold_active!=32 || dut.threshold_requested!=32) $fatal(1,"reset defaults");
        $display("PASS: actual Sobel raster, grayscale left half, binary right half, key-to-video direction, frame-boundary commit, and reset default.");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
