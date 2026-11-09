`timescale 1ns/1ps
// Actual board-size rational mapping, complete processing, and output map.
module canny_resolution_tb;
    localparam W=640,H=480,N=W*H;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,vs=0,dvs=0;
    reg [11:0] x=0,y=0,display_x=0,display_y=0;
    reg [7:0] gray=0;
    wire edge_pixel,valid,busy;
    reg expected[0:N-1];
    integer samples=0,ix,iy,n,count,checked=0,white=0;
    canny_video_map #(.WIDTH(1920),.HEIGHT(1080),.PROCESS_WIDTH(W),.PROCESS_HEIGHT(H)) dut(
        .clk(clk),.rst_n(rst),.de_in(de),.vs_in(vs),.x_in(x),.y_in(y),.gray_in(gray),
        .high_threshold(11'd144),.display_vs(dvs),.display_x(display_x),.display_y(display_y),
        .edge_out(edge_pixel),.valid_out(valid),.busy(busy));
    function [7:0] pixel;
        input integer px,py;
        begin pixel=(px>=481 && px<1441 && py>=181 && py<901) ? 200:20;end
    endfunction
    task ticks;input integer cycles;integer t;
        begin for(t=0;t<cycles;t=t+1) begin @(posedge clk);#1;end end
    endtask
    always @(posedge clk) if(rst && dut.sample_de) begin
        if(dut.sample_x!==samples%W || dut.sample_y!==samples/W)
            $fatal(1,"640x480 sample coordinate gap at %0d: %0d,%0d",samples,dut.sample_x,dut.sample_y);
        samples=samples+1;
    end
    initial begin
        $readmemh("test_output/canny_640x480_expected.hex",expected);
        ticks(4);@(negedge clk);rst=1;ticks(4);
        @(negedge clk);vs=1;dvs=1;ticks(4);
        @(negedge clk);vs=0;dvs=0;ticks(16);
        // Include every source row, including the 600 discarded rows. Sample
        // x positions plus an explicitly rejected non-sample at each row end.
        for(iy=0;iy<1080;iy=iy+1) begin
            for(ix=0;ix<W;ix=ix+1) begin
                @(negedge clk);de=1;x=3*ix;y=iy;gray=pixel(3*ix,iy);
            end
            @(negedge clk);x=1919;gray=pixel(1919,iy);
            @(negedge clk);de=0;ticks(2);
        end
        ticks(20);
        if(samples!=N) $fatal(1,"actual processed sample count %0d, expected 307200",samples);
        count=0;
        while(dut.hysteresis.state!=8) begin
            ticks(1);count=count+1;
            if(count>7000000) $fatal(1,"640x480 map did not converge");
        end
        if(valid) $fatal(1,"640x480 map published outside VS");
        @(negedge clk);dvs=1;ticks(2);@(negedge clk);dvs=0;ticks(3);
        if(!valid) $fatal(1,"640x480 result missing");
        for(iy=0;iy<H;iy=iy+1) begin
            for(ix=0;ix<W;ix=ix+1) begin
                // Check the last source pixel of every enlarged display cell.
                @(negedge clk);display_x=3*ix+2;display_y=((iy+1)*9+3)/4-1;
                ticks(3);
                if(edge_pixel!==expected[iy*W+ix])
                    $fatal(1,"640x480 reference mismatch at %0d,%0d",ix,iy);
                checked=checked+1;if(edge_pixel) white=white+1;
            end
        end
        if(white==0) $fatal(1,"640x480 reference image has no edges");
        $display("PASS: actual 1920x1080 -> 640x480 rational sampling, %0d samples, %0d complete-map BFS comparisons, %0d edge pixels, no cropped source rows",samples,checked,white);
        $finish;
    end
    initial begin #100000000;$fatal(1,"640x480 resolution timeout");end
endmodule
