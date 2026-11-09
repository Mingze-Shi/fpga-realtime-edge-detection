module sc431_sobel_video #(
    parameter REPLAY_FRAMES=2,SELECT_BITS=$clog2(REPLAY_FRAMES),
    parameter AUTO_REPLAY=0,PLAY_FRAMES=6,
    parameter integer WIDTH = 1920,
    parameter integer DEBOUNCE_CYCLES = 2970000,
    parameter integer LONG_PRESS_CYCLES = 148500000,
    parameter integer CANNY_ENABLE = 0,
    parameter integer HEIGHT = 1080,
    parameter integer CANNY_SCALE_LOG2 = 2,
    parameter integer CANNY_WIDTH = WIDTH>>CANNY_SCALE_LOG2,
    parameter integer CANNY_HEIGHT = HEIGHT>>CANNY_SCALE_LOG2,
    parameter integer CANNY_MEDIAN_ENABLE = 0,
    parameter integer SNAPSHOT_ENABLE = 0,
    parameter integer PHOTO_MATCH_ENABLE = 0,
    parameter integer PHOTO_SAMPLE_STEP = 16,
    parameter integer CNN_ENABLE = 0,
    parameter integer CNN_EXPRESSION_ENABLE = 0,
    parameter integer EXPRESSION_ENABLE = 0,
    parameter integer EXPRESSION_STEP_X = 16,
    parameter integer EXPRESSION_STEP_Y = 8
)(
    input clk, input rst_n,
    input increase_n, input decrease_n, input mode_n,
    input de_in, input hs_in, input vs_in,
    input freeze_ack,replay_ack,
    input [SELECT_BITS-1:0] replay_selection_ack,
    input [7:0] red_in, green_in, blue_in,
    output de_out, hs_out, vs_out,
    output [7:0] gray_out,
    output [7:0] red_out, green_out, blue_out,
    output freeze_requested,
    output replay_requested,
    output [SELECT_BITS-1:0] replay_select
,
    output compare_request,
    // Digital exposure: 0 = untouched, 3 = 1/8. Adjusted with SW1/SW2 in mode 1.
    output reg [1:0] expo_shift
);
    reg [11:0] column = 0, row = 0;
    reg de_previous = 0, vs_previous = 0;
    wire [10:0] threshold_requested;
    reg [10:0] threshold_active;
    wire color_requested;
    reg color_active;
    wire user_freeze_toggle,up_event,down_event;
    wire [1:0] mode_requested;
    reg [1:0] display_mode_active;
    wire map_valid_control,work_reset_control,overlay_visible,processed_edge;
    generate if(SNAPSHOT_ENABLE) begin : snapshot_control
        wire freeze_request_int;
        canny_snapshot_control #(.REPLAY_FRAMES(REPLAY_FRAMES),.RELEASE_FRAMES(REPLAY_FRAMES>=6 ? 8:2),
            .AUTO_REPLAY(AUTO_REPLAY),.PLAY_FRAMES(PLAY_FRAMES)) u_control(
            .clk(clk),.rst_n(rst_n),.frame_start(vs_in && !vs_previous),
            .mode_active(display_mode_active),.user_freeze_toggle(user_freeze_toggle),
            .previous_event(up_event),.step_event(up_event || down_event),.freeze_ack(freeze_ack),
            .replay_ack(replay_ack),.replay_selection_ack(replay_selection_ack),.map_valid(map_valid_control),
            .freeze_request(freeze_request_int),.replay_request(replay_requested),.replay_select(replay_select),
            .work_reset(work_reset_control),.overlay_visible(overlay_visible));
        assign freeze_requested = compare_request ? 1'b0 : freeze_request_int;
    end else begin : no_snapshot_control
        assign freeze_requested=user_freeze_toggle;
        assign replay_requested=0;assign replay_select=0;
        assign work_reset_control=0;assign overlay_visible=0;
    end endgenerate
    // 延迟链必须与灰度链等长:
    //   gray_registered(1) + median3x3(4) + sobel_stream(4) = 9 级
    // 改动上面任一段的流水深度时, 这里要同步改, 否则按键切到彩色模式时
    // 画面会横向错位。
    reg [23:0] color_pipe [0:8];
    integer stage;
    mode_key #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES), .LONG_PRESS_CYCLES(LONG_PRESS_CYCLES),
        .DISPLAY_MODES(SNAPSHOT_ENABLE ? 4:2)) u_mode_key(
        .clk(clk), .rst_n(rst_n), .mode_n(mode_n),
        .color_requested(color_requested),.mode_requested(mode_requested),.freeze_requested(user_freeze_toggle)
    );
    threshold_keys #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.SUPPRESS_ENABLE(SNAPSHOT_ENABLE)) u_threshold_keys(
        .clk(clk), .rst_n(rst_n),
        .increase_n(increase_n), .decrease_n(decrease_n),
        .suppress_adjust(display_mode_active>=2 || display_mode_active==1),.up_event(up_event),.down_event(down_event),
        .threshold_requested(threshold_requested)
    );
    // 模式 1 下 SW1/SW2 改为调数字曝光 (右移 0~3 位 = 1/1 ~ 1/8)。
    // 画面过曝时按 SW1 逐级压暗, 按 SW2 恢复; 离开模式 1 保持当前档位。
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) expo_shift<=2'd0;
        else if(display_mode_active==1) begin
            if(up_event)   begin if(expo_shift!=2'd3) expo_shift<=expo_shift+2'd1; end
            else if(down_event) begin if(expo_shift!=2'd0) expo_shift<=expo_shift-2'd1; end
        end
    end
    wire [11:0] xpos = de_previous ? column : 12'd0;
    wire [15:0] luminance = {8'b0,red_in} * 16'd77
                          + {8'b0,green_in} * 16'd150
                          + {8'b0,blue_in} * 16'd29 + 16'd128;
    reg [7:0] gray_registered;
    reg de_registered, hs_registered, vs_registered;
    reg [11:0] x_registered, y_registered;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column<=0; row<=0; de_previous<=0; vs_previous<=0;
            gray_registered<=0; de_registered<=0;
            hs_registered<=0; vs_registered<=0;
            x_registered<=0; y_registered<=0;
            threshold_active<=11'd32;
            color_active<=0;
            display_mode_active<=0;
            for (stage=0;stage<9;stage=stage+1) color_pipe[stage]<=0;
        end else begin
            de_previous<=de_in; vs_previous<=vs_in;
            // Commit only during vertical blanking, before active frame pixels.
            if (vs_in && !vs_previous) begin
                threshold_active<=threshold_requested;
                color_active<=color_requested;
                display_mode_active<=mode_requested;
            end
            if (vs_in && !vs_previous) begin column<=0; row<=0; end
            else if (de_in) column<=xpos+1'b1;
            else if (de_previous) begin column<=0; row<=row+1'b1; end
            gray_registered<=luminance[15:8];
            de_registered<=de_in; hs_registered<=hs_in; vs_registered<=vs_in;
            x_registered<=xpos; y_registered<=row;
            color_pipe[0]<={red_in,green_in,blue_in};
            for (stage=1;stage<9;stage=stage+1) color_pipe[stage]<=color_pipe[stage-1];
        end
    end
    wire [7:0] center_gray, edge_gray, binary_gray;
    wire [11:0] x_output, y_output;

    // 中值滤波: 灰度域, Sobel 之前。边界(前 2 行 / 前 2 列)自动透传原像素。
    wire [7:0]  gray_filtered;
    wire        de_filtered, hs_filtered, vs_filtered;
    wire [11:0] x_filtered, y_filtered;
    median3x3 #(.WIDTH(WIDTH)) u_median(
        .clk(clk), .rst_n(rst_n),
        .de_in(de_registered), .hs_in(hs_registered), .vs_in(vs_registered),
        .x_in(x_registered), .y_in(y_registered), .gray_in(gray_registered),
        .de_out(de_filtered), .hs_out(hs_filtered), .vs_out(vs_filtered),
        .x_out(x_filtered), .y_out(y_filtered), .gray_out(gray_filtered)
    );

    sobel_stream #(.WIDTH(WIDTH)) u_sobel(
        .clk(clk), .rst_n(rst_n),
        .de_in(de_filtered), .hs_in(hs_filtered), .vs_in(vs_filtered),
        .x_in(x_filtered), .y_in(y_filtered), .gray_in(gray_filtered),
        .threshold(threshold_active), .de_out(de_out), .hs_out(hs_out), .vs_out(vs_out),
        .x_out(x_output), .y_out(y_output), .gray_out(center_gray),
        .edge_out(edge_gray), .binary_out(binary_gray)
    );
    generate if(CANNY_ENABLE) begin : canny_enabled
        wire canny_edge,canny_valid,canny_busy;
        reg [5:0] edge_delay;
        reg [7:0] gray_delay[0:7];
        integer ci;
        // Rational coordinate mapping/address/RAM lookup takes three clocks.
        // Six more match the existing nine-clock RGB/DE/HS/VS path.
        canny_video_map #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SCALE_LOG2(CANNY_SCALE_LOG2),
            .PROCESS_WIDTH(CANNY_WIDTH),.PROCESS_HEIGHT(CANNY_HEIGHT),.CONTROL_ENABLE(SNAPSHOT_ENABLE)) u_canny(
            .clk(clk),.rst_n(rst_n),
            .de_in(CANNY_MEDIAN_ENABLE ? de_filtered:de_registered),
            .vs_in(CANNY_MEDIAN_ENABLE ? vs_filtered:vs_registered),
            .x_in(CANNY_MEDIAN_ENABLE ? x_filtered:x_registered),
            .y_in(CANNY_MEDIAN_ENABLE ? y_filtered:y_registered),
            .gray_in(CANNY_MEDIAN_ENABLE ? gray_filtered:gray_registered),
            .high_threshold(threshold_active),.display_vs(vs_in),
            .work_reset(work_reset_control),
            .display_x(CANNY_MEDIAN_ENABLE ? xpos+12'd1:xpos),
            .display_y(CANNY_MEDIAN_ENABLE ? row+12'd1:row),
            .edge_out(canny_edge),.valid_out(canny_valid),.busy(canny_busy));
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                edge_delay<=0;
                for(ci=0;ci<8;ci=ci+1) gray_delay[ci]<=0;
            end else begin
                edge_delay<={edge_delay[4:0],canny_edge};
                gray_delay[0]<=gray_registered;
                for(ci=1;ci<8;ci=ci+1) gray_delay[ci]<=gray_delay[ci-1];
            end
        end
        assign gray_out=x_output<WIDTH/2 ? gray_delay[7]:{8{edge_delay[5]}};
        assign processed_edge=edge_delay[5];
        assign map_valid_control=canny_valid;
    end else begin : sobel_enabled
        assign gray_out = x_output < WIDTH/2 ? center_gray : binary_gray;
        assign processed_edge=binary_gray[7];assign map_valid_control=0;
    end endgenerate
    // Mode 1 overlays the latest completed Canny map on live RGB.
    // Modes 2/3 retain their locked, same-frame snapshot/replay overlay.
    wire live_overlay = CANNY_ENABLE && SNAPSHOT_ENABLE && color_active &&
        display_mode_active==1 && map_valid_control && !work_reset_control;
    reg compare_active;
    reg freeze_toggle_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin compare_active<=0; freeze_toggle_d<=0; end
        else begin
            freeze_toggle_d<=user_freeze_toggle;
            if(display_mode_active!=2) compare_active<=0;
            else if(user_freeze_toggle^freeze_toggle_d) compare_active<=~compare_active;
        end
    end
    wire [23:0] base_rgb = SNAPSHOT_ENABLE && display_mode_active[1] ?
        (overlay_visible && processed_edge ? 24'hff0000:color_pipe[8]) :
        (color_active ? (live_overlay && processed_edge ? 24'hff0000:color_pipe[8]) : {gray_out,gray_out,gray_out});
    // Mode 2 is the left/right compare: left half is the delayed frame, right half is live.
    assign compare_request = SNAPSHOT_ENABLE && display_mode_active==2 && compare_active;
    wire split_divider = compare_request && x_output>=WIDTH/2-2 && x_output<WIDTH/2+2;
    wire [23:0] normal_rgb = split_divider ? 24'hffffff : base_rgb;
    generate if(CNN_ENABLE && CNN_EXPRESSION_ENABLE) begin : cnn_expression_recognition
        // The guide box and the CNN sampling window are the SAME region: a 32x32
        // grid of SX x SY pixels. 32:16 keeps the 2:1 aspect of the training ROI
        // (256x128 downscaled to 32x32), and deriving FACE_W/FACE_H from the step
        // parameters means the drawn box can never drift from what the core sees.
        localparam integer CNN_SX_LOG2=5,CNN_SY_LOG2=4;
        localparam integer FACE_W=32*(1<<CNN_SX_LOG2),FACE_H=32*(1<<CNN_SY_LOG2);
        localparam integer FACE_X=(WIDTH-FACE_W)/2,FACE_Y=(HEIGHT-FACE_H)/2;
        wire matched,result_valid,matcher_busy;
        wire signed [31:0] logit0,logit1,logit2,logit3,logit4;
        wire [2:0] class_id; reg [2:0] shown_class;
        taffy_expression_cnn_match #(.ROI_X(FACE_X),.ROI_Y(FACE_Y),
            .STEP_X_LOG2(CNN_SX_LOG2),.STEP_Y_LOG2(CNN_SY_LOG2)) u_match(
            .clk(clk),.rst_n(rst_n),.enable(display_mode_active==1),
            .de(de_registered),.vs(vs_registered),.x(x_registered),.y(y_registered),.gray(gray_registered),
            .matched(matched),.result_valid(result_valid),.busy(matcher_busy),.logit0(logit0),.logit1(logit1),.logit2(logit2),.logit3(logit3),.logit4(logit4),.class_id(class_id));
        reg shown_match,shown_valid;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n)begin shown_match<=0;shown_valid<=0;shown_class<=0;end
            else if(display_mode_active!=1)begin shown_match<=0;shown_valid<=0;shown_class<=0;end
            else if(vs_in && !vs_previous)begin shown_match<=matched;shown_valid<=result_valid;shown_class<=matched ? class_id:3'd0;end
        end
        wire inside_guide=x_output>=FACE_X && x_output<FACE_X+FACE_W &&
            y_output>=FACE_Y && y_output<FACE_Y+FACE_H;
        wire border=inside_guide && (x_output<FACE_X+4 || x_output>=FACE_X+FACE_W-4 ||
            y_output<FACE_Y+4 || y_output>=FACE_Y+FACE_H-4);
        wire text_ink,text_panel;
        cnn_expression_text #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_text(
            .x(x_output),.y(y_output),.class_id(shown_class),.ink(text_ink),.panel(text_panel));
        assign {red_out,green_out,blue_out}=display_mode_active==1 && de_out ?
            (text_panel ? (text_ink ? 24'hffffff:24'h000000):
             (border ? (shown_match ? 24'h00ff00:(shown_valid ? 24'hff4040:24'hffff00)):normal_rgb)):normal_rgb;
    end else if(CNN_ENABLE) begin : cnn_recognition
        localparam integer FACE_W=1024,FACE_H=512;
        localparam integer FACE_X=(WIDTH-FACE_W)/2,FACE_Y=(HEIGHT-FACE_H)/2;
        wire matched,result_valid,matcher_busy;
        wire signed [31:0] logit0,logit1;
        taffy_cnn_match #(.ROI_X(FACE_X),.ROI_Y(FACE_Y)) u_match(
            .clk(clk),.rst_n(rst_n),.enable(display_mode_active==1),
            .de(de_registered),.vs(vs_registered),.x(x_registered),.y(y_registered),.gray(gray_registered),
            .matched(matched),.result_valid(result_valid),.busy(matcher_busy),.logit0(logit0),.logit1(logit1));
        reg shown_match,shown_valid;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n)begin shown_match<=0;shown_valid<=0;end
            else if(display_mode_active!=1)begin shown_match<=0;shown_valid<=0;end
            else if(vs_in && !vs_previous)begin shown_match<=matched;shown_valid<=result_valid;end
        end
        wire inside_guide=x_output>=FACE_X && x_output<FACE_X+FACE_W &&
            y_output>=FACE_Y && y_output<FACE_Y+FACE_H;
        wire border=inside_guide && (x_output<FACE_X+4 || x_output>=FACE_X+FACE_W-4 ||
            y_output<FACE_Y+4 || y_output>=FACE_Y+FACE_H-4);
        wire text_ink,text_panel;
        cnn_status_text #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_text(
            .x(x_output),.y(y_output),.matched(shown_match),.valid_result(shown_valid),.ink(text_ink),.panel(text_panel));
        assign {red_out,green_out,blue_out}=display_mode_active==1 && de_out ?
            (text_panel ? (text_ink ? 24'hffffff:24'h000000):
             (border ? (shown_match ? 24'h00ff00:(shown_valid ? 24'hff4040:24'hffff00)):normal_rgb)):normal_rgb;
    end else if(PHOTO_MATCH_ENABLE && EXPRESSION_ENABLE) begin : expression_recognition
        localparam integer FACE_W=32*EXPRESSION_STEP_X,FACE_H=32*EXPRESSION_STEP_Y;
        localparam integer FACE_X=(WIDTH-FACE_W)/2,FACE_Y=(HEIGHT-FACE_H)/2;
        wire matched,result_valid,matcher_busy;
        wire [2:0] class_id;
        wire [15:0] best_error,second_error;
        taffy_expression_match #(.ROI_X(FACE_X),.ROI_Y(FACE_Y),
            .SAMPLE_STEP_X(EXPRESSION_STEP_X),.SAMPLE_STEP_Y(EXPRESSION_STEP_Y)) u_match(
            .clk(clk),.rst_n(rst_n),.enable(display_mode_active==1),
            .de(de_registered),.vs(vs_registered),.x(x_registered),.y(y_registered),.gray(gray_registered),
            .matched(matched),.result_valid(result_valid),.class_id(class_id),
            .best_error(best_error),.second_error(second_error),.busy(matcher_busy));
        reg [2:0] shown_class;
        reg shown_valid;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin shown_class<=0;shown_valid<=0;end
            else if(display_mode_active!=1) begin shown_class<=0;shown_valid<=0;end
            else if(vs_in && !vs_previous) begin
                shown_class<=matched ? class_id:3'd0;shown_valid<=result_valid;
            end
        end
        wire inside_guide=x_output>=FACE_X && x_output<FACE_X+FACE_W &&
            y_output>=FACE_Y && y_output<FACE_Y+FACE_H;
        wire border=inside_guide && (x_output<FACE_X+4 || x_output>=FACE_X+FACE_W-4 ||
            y_output<FACE_Y+4 || y_output>=FACE_Y+FACE_H-4);
        wire text_ink,text_panel;
        taffy_expression_text #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_text(
            .x(x_output),.y(y_output),.class_id(shown_class),.ink(text_ink),.panel(text_panel));
        assign {red_out,green_out,blue_out}=display_mode_active==1 && de_out ?
            (text_panel ? (text_ink ? 24'hffffff:24'h000000):
             (border ? (shown_class!=0 ? 24'h00ff00:(shown_valid ? 24'hff4040:24'hffff00)):normal_rgb)):normal_rgb;
    end else if(PHOTO_MATCH_ENABLE) begin : photo_recognition
        localparam integer PHOTO_SIDE=64*PHOTO_SAMPLE_STEP;
        localparam integer PHOTO_X=(WIDTH-PHOTO_SIDE)/2, PHOTO_Y=(HEIGHT-PHOTO_SIDE)/2;
        wire matched,result_valid;
        wire [21:0] last_error;
        // Match the same pre-filter grayscale stream used by Canny. The guide
        // uses the existing nine-clock output coordinates, with no new latency.
        taffy_photo_match #(.ROI_X(PHOTO_X),.ROI_Y(PHOTO_Y),.SAMPLE_STEP(PHOTO_SAMPLE_STEP)) u_match(.clk(clk),.rst_n(rst_n),
            .enable(display_mode_active==1),.de(de_registered),.vs(vs_registered),
            .x(x_registered),.y(y_registered),.gray(gray_registered),
            .matched(matched),.result_valid(result_valid),.last_error(last_error));
        wire inside_guide=x_output>=PHOTO_X && x_output<PHOTO_X+PHOTO_SIDE &&
            y_output>=PHOTO_Y && y_output<PHOTO_Y+PHOTO_SIDE;
        wire border=inside_guide && (x_output<PHOTO_X+4 || x_output>=PHOTO_X+PHOTO_SIDE-4 ||
            y_output<PHOTO_Y+4 || y_output>=PHOTO_Y+PHOTO_SIDE-4);
        wire text_ink,text_panel;
        taffy_success_text #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_success_text(
            .x(x_output),.y(y_output),.ink(text_ink),.panel(text_panel));
        assign {red_out,green_out,blue_out}=display_mode_active==1 && de_out ?
            (matched && text_panel ? (text_ink ? 24'hffffff:24'h000000):
             (border ? (matched ? 24'h00ff00:(result_valid ? 24'hff4040:24'hffff00)):normal_rgb)):normal_rgb;
    end else begin : no_photo_recognition
        assign {red_out,green_out,blue_out}=normal_rgb;
    end endgenerate
endmodule
