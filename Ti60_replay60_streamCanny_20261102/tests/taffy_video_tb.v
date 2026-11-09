`timescale 1ns/1ps
module taffy_video_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,hs=0,vs=0,mode_n=1;
    reg [7:0] pixel=0,photo[0:4095];
    reg text_mask[0:5119];
    wire od,oh,ov;
    wire [7:0] r,g,b,gray;
    reg [11:0] text_x=0,text_y=0;
    wire text_ink_full,text_panel_full;
    taffy_success_text full_size_text(.x(text_x),.y(text_y),.ink(text_ink_full),.panel(text_panel_full));
    sc431_sobel_video #(.WIDTH(160),.HEIGHT(144),.PHOTO_MATCH_ENABLE(1),
        .PHOTO_SAMPLE_STEP(2),.DEBOUNCE_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst),.increase_n(1'b1),.decrease_n(1'b1),.mode_n(mode_n),
        .freeze_ack(1'b0),.replay_ack(1'b0),.replay_selection_ack(1'b0),
        .de_in(de),.hs_in(hs),.vs_in(vs),.red_in(pixel),.green_in(pixel),.blue_in(pixel),
        .de_out(od),.hs_out(oh),.vs_out(ov),.red_out(r),.green_out(g),.blue_out(b),.gray_out(gray));
    task ticks;input integer n;begin repeat(n) begin @(posedge clk);#2;end end endtask
    task press;begin @(negedge clk);mode_n=0;ticks(8);@(negedge clk);mode_n=1;ticks(8);end endtask
    integer px,py,input_x=0,input_y=0,checks=0,green_pixels=0,text_pixels=0,tx,ty;
    task frame;input integer negative;
        begin
            @(negedge clk);vs=1;de=0;ticks(5);@(negedge clk);vs=0;ticks(5);
            for(py=0;py<144;py=py+1) begin
                for(px=0;px<160;px=px+1) begin
                    @(negedge clk);de=1;hs=0;pixel=73;input_x=px;input_y=py;
                    if(px>=16 && px<144 && py>=8 && py<136)
                        pixel=negative ? 128:photo[((py-8)/2)*64+(px-16)/2];
                end
                @(negedge clk);de=0;hs=1;ticks(4);
            end
            ticks(12);
        end
    endtask
    reg [8:0] dp=0,hp=0,vp=0;
    reg [7:0] pp[0:8];integer xp[0:8],yp[0:8];
    integer k,warm=0;
    reg guide;reg [23:0] expected;
    always @(posedge clk) if(rst) begin
        for(k=8;k>0;k=k-1) begin pp[k]=pp[k-1];xp[k]=xp[k-1];yp[k]=yp[k-1];end
        pp[0]=pixel;xp[0]=input_x;yp[0]=input_y;
        dp={dp[7:0],de};hp={hp[7:0],hs};vp={vp[7:0],vs};warm=warm+1;
        #1;
        if(warm>9 && {od,oh,ov}!=={dp[8],hp[8],vp[8]}) $fatal(1,"sync latency");
        if(od && dut.display_mode_active==1) begin
            guide=xp[8]>=16 && xp[8]<144 && yp[8]>=8 && yp[8]<136 &&
                (xp[8]<20 || xp[8]>=140 || yp[8]<12 || yp[8]>=132);
            expected=guide ? (dut.photo_recognition.matched ? 24'h00ff00:
                (dut.photo_recognition.result_valid ? 24'hff4040:24'hffff00)):{pp[8],pp[8],pp[8]};
            if(dut.photo_recognition.matched && xp[8]>=0 && xp[8]<160 && yp[8]>=16 && yp[8]<48) begin
                expected=text_mask[(yp[8]-16)*160+xp[8]] ? 24'hffffff:24'h000000;
                if(text_mask[(yp[8]-16)*160+xp[8]]) text_pixels=text_pixels+1;
            end
            if({r,g,b}!==expected) $fatal(1,"guide/RGB misaligned x=%d y=%d got=%h exp=%h",xp[8],yp[8],{r,g,b},expected);
            checks=checks+1;
            if({r,g,b}==24'h00ff00) green_pixels=green_pixels+1;
        end
    end
    initial begin
        $readmemh("assets/taffy/gray.hex",photo);
        $readmemh("assets/taffy/success_text_mask.hex",text_mask);
        // Check actual 1080p coordinates, 2x glyph scaling, and all four edges.
        for(ty=63;ty<=128;ty=ty+1) for(tx=799;tx<=1120;tx=tx+1) begin
            text_x=tx;text_y=ty;#1;
            if(text_panel_full !== (tx>=800 && tx<1120 && ty>=64 && ty<128)) $fatal(1,"1080p text bounds");
            if(tx>=800 && tx<1120 && ty>=64 && ty<128) begin
                if(text_ink_full!==text_mask[((ty-64)/2)*160+(tx-800)/2]) $fatal(1,"1080p glyph scaling");
            end else if(text_ink_full) $fatal(1,"text outside bounds");
        end
        ticks(4);@(negedge clk);rst=1;ticks(12);press;
        repeat(4) frame(0);
        if(!dut.photo_recognition.matched || green_pixels==0 || text_pixels==0) $fatal(1,"matching/green guide/success text missing");
        repeat(2) frame(1);
        if(dut.photo_recognition.matched) $fatal(1,"negative frame result retained");
        press;frame(0);
        if(dut.photo_recognition.result_valid || dut.photo_recognition.matched) $fatal(1,"mode exit retained result");
        $display("PASS: photo matcher video integration, real buttons, RGB/guide coordinates, nine-clock sync, green result, Chinese success text at 1080p, negative/mode clear (%0d pixels).",checks);
        $finish;
    end
    initial begin #5000000;$fatal(1,"timeout");end
endmodule
