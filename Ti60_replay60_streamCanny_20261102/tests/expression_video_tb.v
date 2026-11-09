`timescale 1ns/1ps
module expression_video_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,hs=0,vs=0,mode_n=1;
    reg [7:0] pixel=0,photo[0:4095];
    reg text_mask[0:10239];
    wire od,oh,ov;wire [7:0] r,g,b,gray;
    reg [11:0] tx_full=0,ty_full=0;reg [2:0] full_class=0;
    wire full_ink,full_panel;
    taffy_expression_text fulltext(.x(tx_full),.y(ty_full),.class_id(full_class),.ink(full_ink),.panel(full_panel));
    sc431_sobel_video #(.WIDTH(160),.HEIGHT(112),.PHOTO_MATCH_ENABLE(1),.EXPRESSION_ENABLE(1),
        .EXPRESSION_STEP_X(2),.EXPRESSION_STEP_Y(1),.DEBOUNCE_CYCLES(2)) dut(
        .clk(clk),.rst_n(rst),.increase_n(1'b1),.decrease_n(1'b1),.mode_n(mode_n),
        .freeze_ack(1'b0),.replay_ack(1'b0),.replay_selection_ack(1'b0),
        .de_in(de),.hs_in(hs),.vs_in(vs),.red_in(pixel),.green_in(pixel),.blue_in(pixel),
        .de_out(od),.hs_out(oh),.vs_out(ov),.red_out(r),.green_out(g),.blue_out(b),.gray_out(gray));
    task ticks;input integer n;begin repeat(n) begin @(posedge clk);#2;end end endtask
    task press;begin @(negedge clk);mode_n=0;ticks(8);@(negedge clk);mode_n=1;ticks(8);end endtask
    integer px,py,input_x=0,input_y=0,checks=0,green=0,labels=0,cls,fx,fy;
    task frame;input integer image_class;
        begin
            @(negedge clk);vs=1;de=0;ticks(5);@(negedge clk);vs=0;ticks(5);
            for(py=0;py<112;py=py+1) begin
                for(px=0;px<160;px=px+1) begin
                    @(negedge clk);de=1;hs=0;pixel=73;input_x=px;input_y=py;
                    if(px>=48 && px<112 && py>=40 && py<72)
                        pixel=image_class==0 ? 128:photo[(image_class-1)*1024+(py-40)*32+(px-48)/2];
                end
                @(negedge clk);de=0;hs=1;ticks(4);
            end
            // Allow the sequential 5x5 search to complete before next frame.
            ticks(210000);
        end
    endtask
    reg [8:0] dp=0,hp=0,vp=0;reg [7:0] pp[0:8];integer xp[0:8],yp[0:8];
    integer k,warm=0;reg guide;reg [23:0] expected;
    always @(posedge clk) if(rst) begin
        for(k=8;k>0;k=k-1) begin pp[k]=pp[k-1];xp[k]=xp[k-1];yp[k]=yp[k-1];end
        pp[0]=pixel;xp[0]=input_x;yp[0]=input_y;
        dp={dp[7:0],de};hp={hp[7:0],hs};vp={vp[7:0],vs};warm=warm+1;#1;
        if(warm>9 && {od,oh,ov}!=={dp[8],hp[8],vp[8]}) $fatal(1,"expression video changed sync latency");
        if(od && dut.display_mode_active==1) begin
            guide=xp[8]>=48 && xp[8]<112 && yp[8]>=40 && yp[8]<72 &&
                (xp[8]<52 || xp[8]>=108 || yp[8]<44 || yp[8]>=68);
            expected=guide ? (dut.expression_recognition.shown_class!=0 ? 24'h00ff00:
                (dut.expression_recognition.shown_valid ? 24'hff4040:24'hffff00)):{pp[8],pp[8],pp[8]};
            if(xp[8]>=16 && xp[8]<144 && yp[8]>=16 && yp[8]<32) begin
                expected=text_mask[dut.expression_recognition.shown_class*2048+(yp[8]-16)*128+xp[8]-16] ? 24'hffffff:24'h000000;
                labels=labels+1;
            end
            if({r,g,b}!==expected) $fatal(1,"expression RGB mismatch x=%0d y=%0d",xp[8],yp[8]);
            checks=checks+1;if({r,g,b}==24'h00ff00)green=green+1;
        end
    end
    initial begin
        $readmemh("assets/expressions/samples_1.hex",photo,0,1023);
        $readmemh("assets/expressions/samples_2.hex",photo,1024,2047);
        $readmemh("assets/expressions/samples_3.hex",photo,2048,3071);
        $readmemh("assets/expressions/samples_4.hex",photo,3072,4095);
        $readmemh("assets/expressions/label_masks.hex",text_mask);
        for(cls=0;cls<=4;cls=cls+1) begin
            full_class=cls;
            for(fy=63;fy<=128;fy=fy+1) for(fx=703;fx<=1216;fx=fx+1) begin
                tx_full=fx;ty_full=fy;#1;
                if(full_panel !== (fx>=704 && fx<1216 && fy>=64 && fy<128)) $fatal(1,"expression label bounds");
                if(full_panel && full_ink!==text_mask[cls*2048+((fy-64)/4)*128+(fx-704)/4]) $fatal(1,"expression label glyph");
                if(!full_panel && full_ink) $fatal(1,"expression label outside bounds");
            end
        end
        ticks(4);@(negedge clk);rst=1;ticks(12);press;
        for(cls=1;cls<=4;cls=cls+1) begin
            // Capture closes at the following VS; UI commits on the next VS.
            // Three matching source frames therefore become visible on frame 5.
            repeat(5) frame(cls);
            if(dut.expression_recognition.shown_class!=cls) $fatal(1,"expression class not displayed %0d",cls);
        end
        repeat(3) frame(0);
        if(dut.expression_recognition.shown_class!=0) $fatal(1,"unknown did not replace label");
        if(green==0 || labels==0) $fatal(1,"guide or labels missing");
        press;frame(1);
        if(dut.expression_recognition.matched || dut.expression_recognition.result_valid) $fatal(1,"mode exit retained recognition");
        $display("PASS: four expression labels, unknown, aligned RGB/guide, real mode button, nine-clock sync, 1080p glyphs (%0d pixels).",checks);
        $finish;
    end
    initial begin #100000000;$fatal(1,"expression video timeout");end
endmodule
