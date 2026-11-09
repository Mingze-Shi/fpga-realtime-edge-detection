`timescale 1ns/1ps
// Integration test: REAL controls, Sobel/RGB pipeline and bank allocator, with
// independent pixel/DDR clocks. Memory below is a frame-tag/RGB behavioral model,
// NOT an AXI transaction model and NOT a simulation of the physical DDR IP.
module freeze_video_tb;
    localparam W = 12, H = 6, PIXELS = W * H;
    reg pixel_clk = 0, ddr_clk = 0;
    always #5 pixel_clk = ~pixel_clk;
    always #7 ddr_clk = ~ddr_clk;
    reg rst_n = 0, up_n = 1, down_n = 1, mode_n = 1;
    reg de = 0, hs = 0, vs = 0;
    reg [7:0] red = 0, green = 0, blue = 0;
    wire deo, hso, vso, freeze_requested;
    wire [7:0] ro, go, bo, gray;
    reg wr_sw = 0, rd_sw = 0;
    wire [1:0] wr_bank, rd_bank;
    wire [31:0] wr_address, rd_address;
    wire wr_ack, rd_ack;
    sc431_sobel_video #(
        .WIDTH(W), .DEBOUNCE_CYCLES(4), .LONG_PRESS_CYCLES(60)
    ) video (
        .clk(pixel_clk), .rst_n(rst_n), .increase_n(up_n),
        .decrease_n(down_n), .mode_n(mode_n),
        .de_in(de), .hs_in(hs), .vs_in(vs),
        .red_in(red), .green_in(green), .blue_in(blue),
        .de_out(deo), .hs_out(hso), .vs_out(vso), .gray_out(gray),
        .red_out(ro), .green_out(go), .blue_out(bo),
        .freeze_requested(freeze_requested)
    );
    bank_switch #(
        .FB_NUM(3), .MAX_VID_WIDTH(W), .MAX_VID_HIGHT(H),
        .START_ADDR(0), .VID_DATA_WIDTH(32), .AXI_DATA_WIDTH(256)
    ) banks (
        .ddr_clk(ddr_clk), .rst_n(rst_n), .wr_sw(wr_sw), .rd_sw(rd_sw),
        .freeze_request(freeze_requested), .wr_bank(wr_bank), .rd_bank(rd_bank),
        .wr_sw_ack(wr_ack), .rd_sw_ack(rd_ack),
        .wr_start_addr(wr_address), .rd_start_addr(rd_address)
    );

    reg [23:0] memory [0:3*PIXELS-1];
    integer slot_tag [0:2];
    integer capture_index = 0, capture_tag = 1, capture_phase = 0;
    integer captures = 0;
    reg camera_running = 0, enforce_pin = 0;
    reg [1:0] pinned_bank;
    reg [31:0] pinned_address;
    integer pinned_tag;
    function [23:0] pattern;
        input integer tag, index;
        integer x, y;
        reg [7:0] r, g, b;
        begin
            x = index % W; y = index / W;
            r = tag*11 + x*7 + y*3;
            g = tag*5 + x*3 + y*9;
            b = tag*13 + x*5 + y*7;
            pattern = {r,g,b};
        end
    endfunction

    // Camera continuously writes distinct complete RGB frames to its private
    // bank. A bank descriptor boundary follows all 72 writes. The allocator is
    // real; only pixel storage and capture timing are behavioral abstractions.
    always @(posedge ddr_clk) begin
        if (!rst_n) begin
            capture_index = 0; capture_tag = 1;
            capture_phase = 0; captures = 0; wr_sw <= 0;
        end else if (camera_running) begin
            if (wr_bank == rd_bank)
                $fatal(1, "DDR model: camera/read ownership collision");
            if (capture_phase == 0) begin
                if (enforce_pin && wr_bank == pinned_bank)
                    $fatal(1, "camera attempted to overwrite the frozen frame");
                memory[wr_bank*PIXELS+capture_index] = pattern(capture_tag, capture_index);
                if (capture_index == PIXELS-1) begin
                    slot_tag[wr_bank] = capture_tag;
                    captures = captures + 1;
                    capture_tag = capture_tag + 1;
                    capture_index = 0;
                    capture_phase = 1;
                    wr_sw <= 1;
                end else capture_index = capture_index + 1;
            end else begin
                wr_sw <= 0;
                capture_phase = capture_phase + 1;
                if (capture_phase == 6) capture_phase = 0;
            end
        end else wr_sw <= 0;
        #2;
        if (rst_n && enforce_pin &&
            (rd_bank !== pinned_bank || rd_address !== pinned_address ||
             slot_tag[pinned_bank] != pinned_tag))
            $fatal(1, "frozen frame changed while the camera continued capturing");
    end

    task automatic ticks;
        input integer count;
        integer j;
        begin for (j=0;j<count;j=j+1) begin @(posedge pixel_clk); #2; end end
    endtask
    task automatic read_boundary;
        begin
            @(negedge ddr_clk); rd_sw=1;
            repeat(2) begin @(posedge ddr_clk); #2; end
            @(negedge ddr_clk); rd_sw=0;
            repeat(5) begin @(posedge ddr_clk); #2; end
        end
    endtask
    task automatic short_mode;
        begin
            @(negedge pixel_clk);mode_n=0;ticks(12);
            @(negedge pixel_clk);mode_n=1;ticks(12);
        end
    endtask
    task automatic long_mode;
        begin
            @(negedge pixel_clk);mode_n=0;ticks(90);
            @(negedge pixel_clk);mode_n=1;ticks(12);
        end
    endtask
    task automatic press_up;
        begin
            @(negedge pixel_clk);up_n=0;ticks(12);
            @(negedge pixel_clk);up_n=1;ticks(12);
        end
    endtask

    // 流水深度: gray_registered(1) + median3x3(4) + sobel_stream(4) = 9
    reg [23:0] rgb_ref [0:8];
    reg [8:0] de_ref=0, hs_ref=0, vs_ref=0;
    reg old_vs=0, old_color, commit;
    integer stage, warmup=0, output_pixels=0, frame_pixels=0;
    integer checked_frames=0, frozen_color_frames=0;
    reg [31:0] frame_checksum=0, last_checksum=0;
    reg [23:0] frozen_rgb [0:PIXELS-1];
    reg save_frozen_rgb=0, compare_frozen_rgb=0;
    always @(posedge pixel_clk) begin
        old_color=video.color_active;
        commit=vs && !old_vs;
        old_vs=vs;
        if (!rst_n) begin
            old_vs=0; warmup=0; de_ref=0;hs_ref=0;vs_ref=0;
            for(stage=0;stage<9;stage=stage+1) rgb_ref[stage]=0;
        end else begin
            for(stage=8;stage>0;stage=stage-1) rgb_ref[stage]=rgb_ref[stage-1];
            rgb_ref[0]={red,green,blue};
            de_ref={de_ref[7:0],de};hs_ref={hs_ref[7:0],hs};vs_ref={vs_ref[7:0],vs};
            warmup=warmup+1;
            #1;
            if(warmup>=9 && {deo,hso,vso}!=={de_ref[8],hs_ref[8],vs_ref[8]})
                $fatal(1,"freeze/mode disturbed pixel/HS/VS pipeline alignment");
            if(video.color_active!==old_color && !commit)
                $fatal(1,"display mode changed within a frame");
            if(deo) begin
                if(video.color_active) begin
                    if({ro,go,bo}!==rgb_ref[8])
                        $fatal(1,"RGB pixel/channel corruption at output pixel %0d",frame_pixels);
                    if(save_frozen_rgb) frozen_rgb[frame_pixels]={ro,go,bo};
                    if(compare_frozen_rgb && {ro,go,bo}!==frozen_rgb[frame_pixels])
                        $fatal(1,"replayed color pixel differs at index %0d",frame_pixels);
                end else if({ro,go,bo}!=={gray,gray,gray})
                    $fatal(1,"edge mode lost its monochrome output");
                frame_checksum=frame_checksum+{ro,go,bo};
                frame_pixels=frame_pixels+1;
                output_pixels=output_pixels+1;
            end
        end
    end

    task automatic display_frame;
        input advance;
        integer x,y,reader;
        reg [23:0] pixel;
        begin
            reader=rd_bank;
            if(slot_tag[reader]<0) $fatal(1,"display selected uncaptured frame");
            frame_pixels=0;frame_checksum=0;
            @(negedge pixel_clk);vs=1;de=0;ticks(3);
            @(negedge pixel_clk);vs=0;ticks(3);
            for(y=0;y<H;y=y+1) begin
                for(x=0;x<W;x=x+1) begin
                    @(negedge pixel_clk);de=1;hs=0;
                    pixel=memory[reader*PIXELS+y*W+x];
                    {red,green,blue}=pixel;
                    if(rd_bank!==reader) $fatal(1,"DDR read bank changed during display frame");
                end
                @(negedge pixel_clk);de=0;hs=1;ticks(6);
            end
            ticks(12);
            if(frame_pixels!=PIXELS) $fatal(1,"incomplete frame: %0d pixels",frame_pixels);
            last_checksum=frame_checksum;
            checked_frames=checked_frames+1;
            if(compare_frozen_rgb) frozen_color_frames=frozen_color_frames+1;
            if(advance) read_boundary;
        end
    endtask

    integer i, captures_before;
    reg [31:0] frozen_checksum, previous_checksum;
    reg color_before;
    reg saw_live_change;
    initial begin
        for(i=0;i<3;i=i+1) slot_tag[i]=-1;
        ticks(6);@(negedge pixel_clk);rst_n=1;camera_running=1;ticks(8);
        wait(captures>=2);read_boundary;
        short_mode;display_frame(1);
        if(video.color_active!==1) $fatal(1,"short press did not enable initial full color");

        color_before=video.color_requested;
        fork display_frame(1); long_mode; join
        if(freeze_requested!==1 || video.color_requested!==color_before)
            $fatal(1,"first long press did not freeze exclusively: freeze=%b color=%b previous_color=%b",freeze_requested,video.color_requested,color_before);
        pinned_bank=rd_bank;pinned_address=rd_address;pinned_tag=slot_tag[rd_bank];
        enforce_pin=1;captures_before=captures;
        save_frozen_rgb=1;display_frame(1);save_frozen_rgb=0;
        frozen_checksum=last_checksum;
        compare_frozen_rgb=1;
        repeat(4) begin
            display_frame(1);
            if(last_checksum!==frozen_checksum) $fatal(1,"frozen full-color checksum changed");
        end
        compare_frozen_rgb=0;
        if(captures<=captures_before+2) $fatal(1,"camera did not continue during replay");

        short_mode;display_frame(1);
        if(video.color_active!==0 || freeze_requested!==1)
            $fatal(1,"short press while frozen did not switch display independently");
        press_up;display_frame(1);
        if(video.threshold_active!=40 || freeze_requested!==1 || rd_bank!==pinned_bank)
            $fatal(1,"threshold adjustment lost the held frame");
        short_mode;compare_frozen_rgb=1;display_frame(1);compare_frozen_rgb=0;
        if(video.color_active!==1 || last_checksum!==frozen_checksum)
            $fatal(1,"returning to color lost frozen pixel content");

        // Stop enforcing the old pin before the second long request is consumed.
        // Keep rendering throughout the gesture, then require advancing content.
        enforce_pin=0;color_before=video.color_requested;
        fork display_frame(1); long_mode; join
        if(freeze_requested!==0 || video.color_requested!==color_before)
            $fatal(1,"second long press did not resume exclusively");
        previous_checksum=frozen_checksum;saw_live_change=0;
        repeat(4) begin
            display_frame(1);
            if(last_checksum!==previous_checksum) saw_live_change=1;
            previous_checksum=last_checksum;
        end
        if(!saw_live_change) $fatal(1,"resume did not restore changing live frames");
        camera_running=0;
        $display("PASS: async pixel/DDR integration; SW3 long freeze/resume without color toggle; %0d complete frames/%0d pixels; %0d exact RGB frozen replays with continuing captures; frozen short-mode/threshold changes; aligned HS/VS/DE; changing live video after resume. Behavioral frame memory only, no AXI/DDR-IP claim.",checked_frames,output_pixels,frozen_color_frames);
        $finish;
    end
    initial begin #1000000;$fatal(1,"freeze/video integration timed out");end
endmodule
