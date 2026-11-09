`timescale 1ns/1ps
module replay6_overlay_tb #(parameter AUTO=0);
    localparam W=48,H=36;
    reg clk=0;always #5 clk=~clk;
    reg ddr_clk=0;always #3 ddr_clk=~ddr_clk;
    reg rst=0,de=0,hs=0,vs=0,mode_n=1,up_n=1,down_n=1;
    reg [7:0] red=0,green=0,blue=0;
    wire od,oh,ov,freeze,replay,fa,ra,ready;
    wire [2:0] select_frame,sa;
    wire [7:0] ro,go,bo,gray;
    reg ws=0,rs=0,wa=0,wc=0;reg [3:0] writing=0,committed=0;
    wire [3:0] wb,rb;wire[31:0] write_address;
    integer tags[0:9],source_id=0,serial=0,idpipe[0:2];
    reg expected[0:2*24*18-1];
    sc431_sobel_video #(.REPLAY_FRAMES(6),.AUTO_REPLAY(AUTO),.WIDTH(W),.HEIGHT(H),.CANNY_ENABLE(1),.SNAPSHOT_ENABLE(1),
        .CANNY_SCALE_LOG2(1),.DEBOUNCE_CYCLES(2),.LONG_PRESS_CYCLES(40)) dut(
        .clk(clk),.rst_n(rst),.increase_n(up_n),.decrease_n(down_n),.mode_n(mode_n),
        .freeze_ack(fa),.replay_ack(ra),.replay_selection_ack(sa),
        .de_in(de),.hs_in(hs),.vs_in(vs),.red_in(red),.green_in(green),.blue_in(blue),
        .de_out(od),.hs_out(oh),.vs_out(ov),.gray_out(gray),.red_out(ro),.green_out(go),.blue_out(bo),
        .freeze_requested(freeze),.replay_requested(replay),.replay_select(select_frame));
    replay6_slots #(.STRIDE(8192)) banks(
        .clk(ddr_clk),.rst_n(rst),.read_boundary(rs),.freeze_request(freeze),
        .replay_request(replay),.delay_mode(1'b0),.selection(select_frame),.write_begin(wa),
        .write_done(wc),.committed_slot(committed),.reading_slot(rb),.fault(1'b0),
        .write_ready(ready),.write_slot(wb),.read_slot(rb),.write_address(write_address),
        .frozen(fa),.replay_ready(ra),.selection_ack(sa));
    task ticks;input integer n;integer t;
        begin for(t=0;t<n;t=t+1) begin @(posedge clk);#2;end end
    endtask
    task dticks;input integer n;integer t;
        begin for(t=0;t<n;t=t+1) begin @(posedge ddr_clk);#1;end end
    endtask
    function [23:0] pixel;
        input integer tag,px,py;
        reg [7:0] r,g,b;
        begin
            if(px>=(tag%2 ? 30:20) && px<44 && py>=8 && py<28) begin
                r=180+tag;g=170+2*tag;b=160+3*tag;
            end else begin r=20+tag;g=30+2*tag;b=40+3*tag;end
            pixel={r,g,b};
        end
    endfunction
    task memory_boundary;
        reg [3:0] physical;
        begin
            if(ready)begin
                physical=write_address/8192;tags[physical]=serial%6;serial=serial+1;
                @(negedge ddr_clk);wa=1;dticks(1);
                @(negedge ddr_clk);wa=0;dticks(5);
                @(negedge ddr_clk);wc=1;committed=physical;dticks(1);
                @(negedge ddr_clk);wc=0;dticks(6);
            end
            @(negedge ddr_clk);rs=1;dticks(1);
            @(negedge ddr_clk);rs=0;dticks(6);
            source_id=idpipe[2];idpipe[2]=idpipe[1];idpipe[1]=idpipe[0];idpipe[0]=tags[rb];
        end
    endtask
    integer x,y,f,s,visible_pixels=0,red_pixels=0,color_pixels=0,live_red_pixels=0,warmup=0;
    integer ids[0:8];
    reg [23:0] rgb[0:8];reg [8:0] dp=0,hp=0,vp=0;
    reg ref_edge;
    always @(posedge clk) begin
        if(!rst) begin warmup=0;dp=0;hp=0;vp=0;end
        else begin
            for(s=8;s>0;s=s-1) begin rgb[s]=rgb[s-1];ids[s]=ids[s-1];end
            rgb[0]={red,green,blue};ids[0]=source_id;
            dp={dp[7:0],de};hp={hp[7:0],hs};vp={vp[7:0],vs};warmup=warmup+1;
            #1;
            if(warmup>=9 && {od,oh,ov}!=={dp[8],hp[8],vp[8]}) $fatal(1,"overlay HDMI sync latency");
            if(od) begin
                if(dut.display_mode_active[1]) begin
                    if(dut.overlay_visible) begin
                        ref_edge=expected[(ids[8]%2)*24*18+(dut.y_output>>1)*24+(dut.x_output>>1)];
                        if({ro,go,bo}!==(ref_edge ? 24'hff0000:rgb[8]))
                            $fatal(1,"same-frame red overlay mismatch: id=%0d xy=%0d,%0d got=%h rgb=%h edge=%b",ids[8],dut.x_output,dut.y_output,{ro,go,bo},rgb[8],ref_edge);
                        visible_pixels=visible_pixels+1;if(ref_edge) red_pixels=red_pixels+1;
                        if(!fa || !freeze) $fatal(1,"overlay visible before source lock");
                    end else if({ro,go,bo}!==rgb[8]) $fatal(1,"stale red edges exposed during frame transition");
                end else if(dut.color_active) begin
                    if({ro,go,bo}!==((dut.live_overlay && dut.processed_edge) ? 24'hff0000:rgb[8]))
                        $fatal(1,"live RGB overlay mismatch");
                    if(dut.live_overlay && dut.processed_edge) live_red_pixels=live_red_pixels+1;
                    color_pixels=color_pixels+1;
                end
            end
        end
    end
    task frame;
        begin
            memory_boundary;
            @(negedge clk);vs=1;hs=0;de=0;ticks(4);
            @(negedge clk);vs=0;ticks(16);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    @(negedge clk);de=1;hs=0;{red,green,blue}=pixel(source_id,x,y);
                end
                @(negedge clk);de=0;hs=1;ticks(6);
            end
            ticks(20);
        end
    endtask
    task short_mode;
        begin @(negedge clk);mode_n=0;ticks(12);@(negedge clk);mode_n=1;ticks(12);end
    endtask
    task next_frame;
        input previous;
        begin
            @(negedge clk);up_n=previous;down_n=!previous;ticks(12);
            @(negedge clk);up_n=1;down_n=1;ticks(12);
        end
    endtask
    integer before_red,held_tag,threshold_before;
    initial begin
        $readmemh("test_output/canny_overlay_expected.hex",expected);
        for(f=0;f<10;f=f+1)tags[f]=0;idpipe[0]=0;idpipe[1]=0;idpipe[2]=0;
        ticks(5);@(negedge clk);rst=1;ticks(8);
        for(f=0;f<5;f=f+1) frame;
        short_mode;
        for(f=0;f<12;f=f+1) frame;
        if(dut.display_mode_active!=1 || color_pixels< W*H || live_red_pixels==0 || freeze || replay)
            $fatal(1,"first SW3 press must show live RGB with red Canny edges");
        short_mode;
        for(f=0;f<12;f=f+1) frame;
        if(dut.display_mode_active!=2 || red_pixels==0 || visible_pixels<W*H) $fatal(1,"red snapshot overlay absent");
        short_mode;
        for(f=0;f<(AUTO ? 60:12);f=f+1) frame;
        if(dut.display_mode_active!==3 || ra!==1'b1) $fatal(1,"six-frame replay entry");
        if(AUTO && (select_frame!==0 || dut.overlay_visible!==1'b1)) $fatal(1,"autoplay did not finish on newest with fresh overlay");
        held_tag=source_id;threshold_before=dut.threshold_requested;before_red=red_pixels;
        repeat(6)begin
            next_frame(0); // SW1: older
            for(f=0;f<10;f=f+1)frame;
            held_tag=(held_tag+5)%6;
            if(source_id!=held_tag || dut.threshold_requested!=threshold_before)
                $fatal(1,"six-frame previous / threshold suppression");
        end
        repeat(6)begin
            next_frame(1); // SW2: newer
            for(f=0;f<10;f=f+1)frame;
            held_tag=(held_tag+1)%6;
            if(source_id!=held_tag)$fatal(1,"six-frame next");
        end
        if(red_pixels==before_red)$fatal(1,"no regenerated overlays");
        @(negedge clk);mode_n=0;ticks(100);@(negedge clk);mode_n=1;ticks(12);
        for(f=0;f<(AUTO ? 60:22);f=f+1) frame;
        if(dut.display_mode_active!=3 || !ra || !dut.overlay_visible) $fatal(1,"long refresh consumed once without short mode event");
        short_mode;
        for(f=0;f<6;f=f+1) frame;
        if(dut.display_mode_active!=0 || replay || freeze) $fatal(1,"four-mode wrap or live restore");
        $display("PASS: four display modes, full RGB preserved except pure-red edge pixels, same-frame overlay with three-frame modeled prefetch, asynchronous DDR lock/selection ack, six-frame previous/next, unchanged replay threshold, long refresh, live exit and nine-cycle sync");
        $finish;
    end
    initial begin #20000000;$fatal(1,"overlay timeout");end
endmodule
