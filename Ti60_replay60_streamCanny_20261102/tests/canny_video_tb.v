`timescale 1ns/1ps
module canny_video_tb #(parameter MEDIAN=0, LIVE_OVERLAY=0);
    localparam W=48,H=36;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,hs=0,vs=0,mode_n=1,up_n=1,down_n=1;
    reg [7:0] red=0,green=0,blue=0;
    wire od,oh,ov,freeze;wire [7:0] gray,ro,go,bo;
    sc431_sobel_video #(.WIDTH(W),.HEIGHT(H),.CANNY_ENABLE(1),
        .CANNY_SCALE_LOG2(1),.CANNY_MEDIAN_ENABLE(MEDIAN),.SNAPSHOT_ENABLE(LIVE_OVERLAY),.DEBOUNCE_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst),.increase_n(up_n),.decrease_n(down_n),.mode_n(mode_n),
        .freeze_ack(1'b0),.replay_ack(1'b0),.replay_selection_ack(1'b0),
        .de_in(de),.hs_in(hs),.vs_in(vs),.red_in(red),.green_in(green),.blue_in(blue),
        .de_out(od),.hs_out(oh),.vs_out(ov),.gray_out(gray),
        .red_out(ro),.green_out(go),.blue_out(bo),.freeze_requested(freeze));
    reg expected[0:24*18-1];
    reg [8:0] dp=0,hp=0,vp=0;
    reg [23:0] rgb[0:8];reg [7:0] gp[0:8];
    integer i,j,f,s,warmup=0,edge_pixels=0,color_pixels=0,white=0,red_pixels=0;
    reg [15:0] lum;
    integer capture_threshold=32,display_threshold=32;
    always @(posedge clk) begin
        if(!rst) begin dp=0;hp=0;vp=0;warmup=0;capture_threshold=32;display_threshold=32;end
        else begin
            if(dut.canny_enabled.u_canny.hysteresis.state==0 &&
               dut.canny_enabled.u_canny.fv && !dut.canny_enabled.u_canny.fv_previous)
                capture_threshold=dut.threshold_active;
            if(dut.canny_enabled.u_canny.hysteresis.state==8 &&
               vs && !dut.canny_enabled.u_canny.display_vs_previous)
                display_threshold=capture_threshold;
            for(s=8;s>0;s=s-1) begin rgb[s]=rgb[s-1];gp[s]=gp[s-1];end
            rgb[0]={red,green,blue};lum=red*77+green*150+blue*29+128;gp[0]=lum[15:8];
            dp={dp[7:0],de};hp={hp[7:0],hs};vp={vp[7:0],vs};warmup=warmup+1;
            #1;
            if(warmup>=9 && {od,oh,ov}!=={dp[8],hp[8],vp[8]}) $fatal(1,"Canny changed HDMI sync");
            if(od) begin
                if(dut.color_active) begin
                    if(LIVE_OVERLAY && dut.map_valid_control && dut.processed_edge) begin
                        if({ro,go,bo}!==24'hff0000) $fatal(1,"live Canny edge not red");
                        red_pixels=red_pixels+1;
                    end else if({ro,go,bo}!==rgb[8]) $fatal(1,"Canny color bypass alignment");
                    color_pixels=color_pixels+1;
                end else begin
                    if({ro,go,bo}!=={gray,gray,gray}) $fatal(1,"Canny monochrome channels");
                    if(dut.x_output<W/2) begin
                        if(gray!==gp[8]) $fatal(1,"Canny grayscale alignment");
                    end else if(dut.canny_enabled.canny_valid) begin
                        if(display_threshold==2032) begin
                            if(gray!==0) $fatal(1,"high threshold did not suppress Canny map");
                        end else if(dut.x_output+MEDIAN<W && dut.y_output+MEDIAN<H) begin
                        if(gray!=={8{expected[((dut.y_output+MEDIAN)>>1)*24+((dut.x_output+MEDIAN)>>1)]}})
                            $fatal(1,"Canny map alignment x=%0d y=%0d got=%0d",dut.x_output,dut.y_output,gray);
                        end else if(gray!==0) $fatal(1,"Canny padded display boundary");
                        edge_pixels=edge_pixels+1;
                        if(gray==255) white=white+1;
                    end else if(gray!==0) $fatal(1,"uninitialized Canny frame exposed");
                end
            end
        end
    end
    task ticks;input integer n;integer t;
        begin for(t=0;t<n;t=t+1) begin @(posedge clk);#2;end end
    endtask
    task frame;
        begin
            @(negedge clk);vs=1;de=0;hs=0;ticks(4);
            @(negedge clk);vs=0;ticks(16);
            for(j=0;j<H;j=j+1) begin
                for(i=0;i<W;i=i+1) begin
                    @(negedge clk);de=1;hs=0;
                    red=i<30 ? 0:255;green=red;blue=red;
                end
                @(negedge clk);de=0;hs=1;ticks(6);
            end
            ticks(20);
        end
    endtask
    task toggle_color;
        begin
            @(negedge clk);mode_n=0;ticks(12);
            @(negedge clk);mode_n=1;ticks(12);
        end
    endtask
    task press_threshold;
        input increase;
        begin
            @(negedge clk);up_n=!increase;down_n=increase;ticks(12);
            @(negedge clk);up_n=1;down_n=1;ticks(12);
        end
    endtask
    initial begin
        if(MEDIAN) $readmemh("test_output/canny_video_median_expected.hex",expected);
        else $readmemh("test_output/canny_video_expected.hex",expected);
        ticks(5);@(negedge clk);rst=1;ticks(10);
        for(f=0;f<10;f=f+1) frame;
        if(edge_pixels<864 || white==0) $fatal(1,"no completed Canny map displayed");
        toggle_color;frame;
        if(color_pixels!=W*H) $fatal(1,"color bypass pixel count");
        if(LIVE_OVERLAY) begin
            if(red_pixels==0 || dut.display_mode_active!=1) $fatal(1,"no red edges after one SW3 press");
            $display("PASS: median=%0d, first SW3 release overlays %0d pure-red edge pixels on full RGB, nine-cycle alignment",MEDIAN,red_pixels);
            $finish;
        end
        toggle_color;frame;
        if(dut.color_active) $fatal(1,"cannot return to Canny");
        repeat(250) press_threshold(1);
        if(dut.threshold_requested!=2032 || dut.threshold_active!=32) $fatal(1,"Canny key/frame threshold commit");
        for(f=0;f<8;f=f+1) frame;
        if(display_threshold!=2032) $fatal(1,"updated Canny threshold never published");
        repeat(250) press_threshold(0);
        white=0;
        for(f=0;f<8;f=f+1) frame;
        if(display_threshold!=32 || white==0) $fatal(1,"lower threshold did not restore Canny edges");
        @(negedge clk);rst=0;ticks(3);
        if(dut.canny_enabled.canny_valid!==0) $fatal(1,"Canny reset validity");
        $display("PASS: integrated Canny (median=%0d), decimation, exact map, spatial correction, nine-cycle HDMI/RGB/grayscale alignment, color mode, threshold increase/decrease and delayed complete-map update, reset",MEDIAN);
        $finish;
    end
    initial begin #10000000;$fatal(1,"Canny video timeout");end
endmodule
