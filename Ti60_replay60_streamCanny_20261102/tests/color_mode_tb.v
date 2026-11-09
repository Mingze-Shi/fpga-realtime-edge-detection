`timescale 1ns/1ps
module color_mode_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0,up_n=1,down_n=1,mode_n=1,de=0,hs=0,vs=0;
    reg [7:0] red=0,green=0,blue=0;
    wire deo,hso,vso;
    wire [7:0] ro,go,bo,gray;
    sc431_sobel_video #(.WIDTH(12),.DEBOUNCE_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.increase_n(up_n),.decrease_n(down_n),.mode_n(mode_n),
        .de_in(de),.hs_in(hs),.vs_in(vs),.red_in(red),.green_in(green),.blue_in(blue),
        .de_out(deo),.hs_out(hso),.vs_out(vso),.gray_out(gray),
        .red_out(ro),.green_out(go),.blue_out(bo)
    );
    task ticks;input integer n;integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk);#2;end end
    endtask
    task press_mode;
        begin @(negedge clk);mode_n=0;ticks(12);@(negedge clk);mode_n=1;ticks(12);end
    endtask
    task press_up;
        begin @(negedge clk);up_n=0;ticks(12);@(negedge clk);up_n=1;ticks(12);end
    endtask
    task frame;
        integer x,y;
        begin
            @(negedge clk);vs=1;de=0;ticks(3);@(negedge clk);vs=0;ticks(3);
            for(y=0;y<6;y=y+1) begin
                for(x=0;x<12;x=x+1) begin
                    @(negedge clk);de=1;hs=0;
                    red=x*17+y*5;green=x*7+y*9;blue=220-x*9-y*3;
                end
                @(negedge clk);de=0;hs=1;ticks(6);
            end
            ticks(12);
        end
    endtask
    // 流水深度: gray_registered(1) + median3x3(4) + sobel_stream(4) = 9
    reg [23:0] rgb_ref[0:8];
    reg [8:0] de_ref=0,hs_ref=0,vs_ref=0;
    reg old_mode,old_vs=0,commit;
    integer stage,color_pixels=0,edge_pixels=0,warmup=0;
    always @(posedge clk) begin
        old_mode=dut.color_active;
        commit=vs && !old_vs;
        old_vs=vs;
        if(!rst_n) begin
            old_vs=0;de_ref=0;hs_ref=0;vs_ref=0;warmup=0;
            for(stage=0;stage<9;stage=stage+1) rgb_ref[stage]=0;
        end else begin
            for(stage=8;stage>0;stage=stage-1) rgb_ref[stage]=rgb_ref[stage-1];
            rgb_ref[0]={red,green,blue};
            de_ref={de_ref[7:0],de};hs_ref={hs_ref[7:0],hs};vs_ref={vs_ref[7:0],vs};
            warmup=warmup+1;
            #1;
            // Existing Sobel reset initializes HS/VS high; compare after flush.
            if(warmup>=9 && {deo,hso,vso}!=={de_ref[8],hs_ref[8],vs_ref[8]}) $fatal(1,"video sync latency changed");
            if(dut.color_active!=old_mode && !commit) $fatal(1,"mode changed outside frame boundary");
            if(deo) begin
                if(dut.color_active) begin
                    if({ro,go,bo}!==rgb_ref[8]) $fatal(1,"RGB channel order or pixel latency incorrect");
                    color_pixels=color_pixels+1;
                end else begin
                    if({ro,go,bo}!=={gray,gray,gray}) $fatal(1,"edge mode no longer monochrome");
                    edge_pixels=edge_pixels+1;
                end
            end
        end
    end
    initial begin
        ticks(6);@(negedge clk);rst_n=1;ticks(8);frame;
        if(dut.color_active!==0 || edge_pixels!=72) $fatal(1,"default edge mode");
        repeat(3) begin @(negedge clk);mode_n=0;ticks(2);@(negedge clk);mode_n=1;ticks(3);end
        ticks(10);
        if(dut.color_requested!==0) $fatal(1,"button bounce toggled mode");
        @(negedge clk);mode_n=0;ticks(12);
        if(dut.color_requested!==0 || dut.color_active!==0) $fatal(1,"short press must wait for release");
        ticks(50);
        if(dut.color_requested!==0) $fatal(1,"held short press changed color before release");
        @(negedge clk);mode_n=1;ticks(12);
        if(dut.color_requested!==1 || dut.color_active!==0) $fatal(1,"released short request should wait for frame");
        color_pixels=0;frame;
        if(dut.color_active!==1 || color_pixels!=72) $fatal(1,"full-color frame including first rows missing");
        press_up;
        if(dut.threshold_requested!=40 || dut.threshold_active!=32) $fatal(1,"threshold request in color mode");
        color_pixels=0;frame;
        if(dut.threshold_active!=40 || color_pixels!=72) $fatal(1,"color mode lost threshold control");
        press_mode;edge_pixels=0;frame;
        if(dut.color_active!==0 || edge_pixels!=72 || dut.threshold_active!=40) $fatal(1,"return to edge mode lost threshold");
        fork
            frame;
            begin wait(de===1);press_mode;if(dut.color_active!==0) $fatal(1,"mid-frame press changed current frame");end
        join
        if(dut.color_requested!==1 || dut.color_active!==0) $fatal(1,"mid-frame request handling");
        color_pixels=0;frame;
        if(dut.color_active!==1 || color_pixels!=72) $fatal(1,"next-frame color commit failed");
        @(negedge clk);rst_n=0;ticks(4);
        if(dut.color_active!==0 || dut.color_requested!==0 || dut.threshold_active!=32) $fatal(1,"reset defaults");
        $display("PASS: mode debounce, one toggle per hold, frame-boundary switching, full RGB pixel/channel/sync alignment, threshold retention and reset.");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
