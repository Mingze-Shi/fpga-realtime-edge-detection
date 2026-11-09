`timescale 1ns/1ps
// Full video integration, including coordinate generation and 5x5 median.
// Change frame brightness without resetting line RAM; randomise blanking data.
module canny_flat_video_tb;
    localparam W=96,H=40;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0;
    reg [7:0] pixel=0;
    wire dout,hout,vout;wire [7:0] gray;
    sc431_sobel_video #(.WIDTH(W),.HEIGHT(H),.CANNY_ENABLE(1),
        .CANNY_STREAM_ENABLE(1),.CANNY_MEDIAN_ENABLE(1)) dut(
        .clk(clk),.rst_n(rst_n),.increase_n(1'b1),.decrease_n(1'b1),.mode_n(1'b1),
        .de_in(de),.hs_in(hs),.vs_in(vs),.freeze_ack(1'b0),.replay_ack(1'b0),
        .replay_selection_ack(1'b0),.red_in(pixel),.green_in(pixel),.blue_in(pixel),
        .de_out(dout),.hs_out(hout),.vs_out(vout),.gray_out(gray));
    integer frame,r,c,level,amplitude,edges,samples,noise;
    reg [31:0] rng=32'h5a17c3e9;
    task random_pixel;
        begin rng=rng^(rng<<13);rng=rng^(rng>>17);rng=rng^(rng<<5);pixel=rng[7:0];end
    endtask
    always @(posedge clk) begin
        #1;
        if(rst_n && dout) begin
            samples=samples+1;
            if(dut.processed_edge===1'b1) edges=edges+1;
            else if(dut.processed_edge!==1'b0) $fatal(1,"unknown edge in frame %0d",frame);
        end
    end
    initial begin
        edges=0;samples=0;
        repeat(5)@(negedge clk);rst_n=1;
        for(frame=0;frame<7;frame=frame+1) begin
            case(frame)
                0:begin level=0;amplitude=0;end
                1:begin level=255;amplitude=0;end
                2:begin level=16;amplitude=0;end
                3:begin level=128;amplitude=0;end
                4:begin level=16;amplitude=2;end
                5:begin level=16;amplitude=8;end
                6:begin level=32;amplitude=16;end
            endcase
            @(negedge clk);de=0;vs=1;
            repeat(8)@(negedge clk);
            vs=0;repeat(64)@(negedge clk);edges=0;samples=0;
            for(r=0;r<H;r=r+1) begin
                for(c=0;c<W;c=c+1) begin
                    @(negedge clk);de=1;random_pixel;
                    noise=amplitude==0 ? 0 : rng%(2*amplitude+1)-amplitude;
                    pixel=level+noise;
                end
                @(negedge clk);de=0;
                repeat(5)begin @(negedge clk);random_pixel;end
            end
            repeat(80)@(negedge clk);
            $display("flat-video frame=%0d level=%0d noise=+/- %0d edges=%0d samples=%0d",frame,level,amplitude,edges,samples);
            if(samples!=W*H)$fatal(1,"lost raster samples");
            if(frame<=4 && edges!=0)$fatal(1,"false edges on constant/low-noise image");
        end
        $display("PASS: full 5x5 video path, flat frames, frame brightness changes, low noise and random blanking");
        $finish;
    end
    initial begin #2000000;$fatal(1,"timeout");end
endmodule
