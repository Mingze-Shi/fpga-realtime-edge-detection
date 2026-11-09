// Metadata only: lock existing DDR RAW slots and drain prefetched video before
// computing Canny. Optional autoplay traverses oldest to newest without maps.
module canny_snapshot_control #(parameter SETTLE_FRAMES=4,RELEASE_FRAMES=2,REPLAY_FRAMES=2,SELECT_BITS=$clog2(REPLAY_FRAMES),
    parameter AUTO_REPLAY=0,PLAY_FRAMES=6)(
    input clk,rst_n,frame_start,
    input [1:0] mode_active,
    input user_freeze_toggle,step_event,previous_event,
    input freeze_ack,replay_ack,map_valid,
    input [SELECT_BITS-1:0] replay_selection_ack,
    output freeze_request,replay_request,
    output reg [SELECT_BITS-1:0] replay_select,
    output work_reset,overlay_visible
);
    localparam LIVE=0,SETTLE=1,PROCESS=2,REFRESH=3;
    reg [1:0] phase;
    localparam PLAY_WAIT=PLAY_FRAMES>SETTLE_FRAMES ? PLAY_FRAMES:SETTLE_FRAMES;
    localparam COUNTER_BITS=$clog2(PLAY_WAIT+RELEASE_FRAMES+SETTLE_FRAMES+1);
    reg [COUNTER_BITS-1:0] frames;
    reg playing;
    reg previous_toggle,manual_freeze;
    reg [1:0] previous_mode;
    (* async_reg="true" *) reg [SELECT_BITS+1:0] ack_meta,ack_sync;
    wire snapshot=mode_active[1];
    wire long_event=user_freeze_toggle!=previous_toggle;
    wire source_ready=ack_sync[0] && (mode_active!=3 ||
        (ack_sync[1] && ack_sync[SELECT_BITS+1:2]==replay_select));
    assign freeze_request=snapshot ? phase!=REFRESH:manual_freeze;
    assign replay_request=mode_active==3 && phase!=REFRESH;
    assign work_reset=snapshot ? phase!=PROCESS:phase!=LIVE;
    assign overlay_visible=snapshot && phase==PROCESS && source_ready && map_valid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            phase<=LIVE;frames<=0;previous_toggle<=0;manual_freeze<=0;
            previous_mode<=0;ack_meta<=0;ack_sync<=0;replay_select<=0;playing<=0;
        end else begin
            ack_meta<={replay_selection_ack,replay_ack,freeze_ack};ack_sync<=ack_meta;
            previous_toggle<=user_freeze_toggle;previous_mode<=mode_active;
            if(!snapshot) begin
                phase<=LIVE;frames<=0;replay_select<=0;playing<=0;
                if(long_event) manual_freeze<=~manual_freeze;
            end else if(mode_active!=previous_mode) begin
                phase<=SETTLE;frames<=0;
                replay_select<=(AUTO_REPLAY && mode_active==3) ? REPLAY_FRAMES-1:0;
                playing<=AUTO_REPLAY && mode_active==3;
            end else if(long_event) begin
                phase<=REFRESH;frames<=0;
                replay_select<=(AUTO_REPLAY && mode_active==3) ? REPLAY_FRAMES-1:0;
                playing<=AUTO_REPLAY && mode_active==3;
            end else if(mode_active>=2 && step_event && phase!=REFRESH && (REPLAY_FRAMES==2 || source_ready)) begin
                if(REPLAY_FRAMES==2)replay_select<=~replay_select;
                else if(previous_event)replay_select<=replay_select==REPLAY_FRAMES-1 ? 0:replay_select+1'b1;
                else replay_select<=replay_select==0 ? REPLAY_FRAMES-1:replay_select-1'b1;
                phase<=SETTLE;frames<=0;playing<=0;
            end else case(phase)
                LIVE:begin phase<=SETTLE;frames<=0;end
                SETTLE:if(!source_ready) frames<=0;
                    else if(frame_start) begin
                        // Count only acknowledged display frames. Keep Canny reset
                        // throughout playback; the final frame gets a fresh map.
                        if(frames==(playing ? PLAY_WAIT:SETTLE_FRAMES)-1) begin
                            frames<=0;
                            if(playing && replay_select!=0) replay_select<=replay_select-1'b1;
                            else begin phase<=PROCESS;playing<=0;end
                        end
                        else frames<=frames+1'b1;
                    end
                PROCESS:if(!source_ready) begin phase<=SETTLE;frames<=0;end
                REFRESH:if(ack_sync[0] || ack_sync[1]) frames<=0;
                    else if(frame_start) begin
                        if(frames==RELEASE_FRAMES-1) begin phase<=SETTLE;frames<=0;end
                        else frames<=frames+1'b1;
                    end
            endcase
        end
    end
endmodule
