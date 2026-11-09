// Four fixed face patterns, not a trained CNN. See tools/expression_model.py.
// One shared SAD engine and synchronous 4-bit memories. No full RGB frame RAM.
module taffy_expression_match #(
    parameter integer ROI_X=704, ROI_Y=412,
    parameter integer SAMPLE_STEP_X=16, SAMPLE_STEP_Y=8,
    parameter integer MAX_ERROR=1100, MIN_MARGIN=70, MIN_GRAY_RANGE=3,
    parameter integer CONFIRM_FRAMES=3
)(
    input clk, rst_n, enable, de, vs,
    input [11:0] x,y,
    input [7:0] gray,
    output reg matched, result_valid,
    output reg [2:0] class_id,
    output reg [15:0] best_error, second_error,
    output busy
);
    localparam IDLE=0, READ=1, ACCUMULATE=2, FINISH_CLASS=3, DECIDE=4;
    localparam integer STREAK_BITS=CONFIRM_FRAMES<2 ? 1:$clog2(CONFIRM_FRAMES+1);
    reg [2:0] state;
    reg vs_previous, malformed, write_bank, match_bank;
    reg [10:0] sample_count;
    reg [13:0] sample_sum;
    reg [3:0] minimum_gray, maximum_gray, frame_mean, frame_range;
    reg [3:0] samples[0:2047];
    reg [3:0] templates[0:4095];
    initial $readmemh("assets/expressions/templates.hex",templates);
    wire [11:0] dx=x-ROI_X,dy=y-ROI_Y;
    wire sample=enable && de && x>=ROI_X && y>=ROI_Y &&
        dx<32*SAMPLE_STEP_X && dy<32*SAMPLE_STEP_Y &&
        dx%SAMPLE_STEP_X==SAMPLE_STEP_X/2 && dy%SAMPLE_STEP_Y==SAMPLE_STEP_Y/2;
    wire [4:0] sx=dx/SAMPLE_STEP_X,sy=dy/SAMPLE_STEP_Y;
    always @(posedge clk) if(sample) samples[{write_bank,sy,sx}]<=gray[7:4];
    reg [1:0] reference_class;
    reg [9:0] scan_address;
    reg [2:0] shift_x,shift_y;
    wire [4:0] rx=scan_address[4:0]+shift_x-5'd2;
    wire [4:0] ry=scan_address[9:5]+shift_y-5'd2;
    reg [3:0] sample_q,template_q;
    always @(posedge clk) if(state==READ) begin
        sample_q<=samples[{match_bank,ry,rx}];
        template_q<=templates[{reference_class,scan_address}];
    end
    // Generated reference means: floor(sum/1024). expression_model.py updates these.
    function [3:0] reference_mean;
        input [1:0] cls;
        begin
            case(cls)
                0:reference_mean=4'd12;
                1:reference_mean=4'd12;
                2:reference_mean=4'd12;
                default:reference_mean=4'd12;
            endcase
        end
    endfunction
    wire signed [6:0] delta=$signed({3'b0,sample_q})-$signed({3'b0,template_q})-
        $signed({3'b0,frame_mean})+$signed({3'b0,reference_mean(reference_class)});
    wire [6:0] absolute_delta=delta[6] ? -delta:delta;
    wire selected=scan_address[4:0]>=2 && scan_address[4:0]<30 &&
        ((scan_address[9:5]>=4 && scan_address[9:5]<16) ||
         (scan_address[9:5]>=17 && scan_address[9:5]<30));
    reg [15:0] error_sum,class_best,global_best,global_second;
    reg [2:0] winning_class,previous_class;
    reg [STREAK_BITS-1:0] streak;
    wire [15:0] next_sum=error_sum+(selected ? {9'b0,absolute_delta}:16'd0);
    assign busy=state!=IDLE;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;vs_previous<=0;malformed<=0;write_bank<=0;match_bank<=1;
            sample_count<=0;sample_sum<=0;minimum_gray<=15;maximum_gray<=0;
            frame_mean<=0;frame_range<=0;reference_class<=0;scan_address<=0;
            shift_x<=0;shift_y<=0;error_sum<=0;class_best<=65535;
            global_best<=65535;global_second<=65535;winning_class<=0;
            matched<=0;result_valid<=0;class_id<=0;best_error<=65535;second_error<=65535;
            previous_class<=0;streak<=0;
        end else begin
            vs_previous<=vs;
            if(!enable) begin
                state<=IDLE;malformed<=0;sample_count<=0;sample_sum<=0;
                minimum_gray<=15;maximum_gray<=0;
                matched<=0;result_valid<=0;class_id<=0;previous_class<=0;streak<=0;
                best_error<=65535;second_error<=65535;
            end else if(vs && !vs_previous) begin
                if(sample_count==1024 && !malformed && state==IDLE) begin
                    match_bank<=write_bank;write_bank<=~write_bank;
                    frame_mean<=sample_sum[13:10];frame_range<=maximum_gray-minimum_gray;
                    reference_class<=0;scan_address<=0;shift_x<=0;shift_y<=0;
                    error_sum<=0;class_best<=65535;global_best<=65535;global_second<=65535;
                    winning_class<=0;state<=READ;
                end else begin
                    state<=IDLE;matched<=0;result_valid<=0;class_id<=0;previous_class<=0;streak<=0;
                end
                malformed<=0;sample_count<=0;sample_sum<=0;minimum_gray<=15;maximum_gray<=0;
            end else begin
                if(sample) begin
                    if(sample_count>=1024 || {1'b0,sy,sx}!=sample_count) malformed<=1;
                    if(sample_count<1025) sample_count<=sample_count+1'b1;
                    sample_sum<=sample_sum+{10'b0,gray[7:4]};
                    if(gray[7:4]<minimum_gray) minimum_gray<=gray[7:4];
                    if(gray[7:4]>maximum_gray) maximum_gray<=gray[7:4];
                end
                case(state)
                    READ:state<=ACCUMULATE;
                    ACCUMULATE:begin
                        if(scan_address==1023) begin
                            if(next_sum<class_best) class_best<=next_sum;
                            scan_address<=0;error_sum<=0;
                            if(shift_x==4 && shift_y==4) state<=FINISH_CLASS;
                            else begin
                                if(shift_x==4) begin shift_x<=0;shift_y<=shift_y+1'b1;end
                                else shift_x<=shift_x+1'b1;
                                state<=READ;
                            end
                        end else begin
                            error_sum<=next_sum;scan_address<=scan_address+1'b1;state<=READ;
                        end
                    end
                    FINISH_CLASS:begin
                        if(class_best<global_best) begin
                            global_second<=global_best;global_best<=class_best;winning_class<={1'b0,reference_class}+3'd1;
                        end else if(class_best<global_second) global_second<=class_best;
                        if(reference_class==3) state<=DECIDE;
                        else begin
                            reference_class<=reference_class+1'b1;scan_address<=0;
                            shift_x<=0;shift_y<=0;error_sum<=0;class_best<=65535;state<=READ;
                        end
                    end
                    DECIDE:begin
                        state<=IDLE;result_valid<=1;best_error<=global_best;second_error<=global_second;
                        if(frame_range>=MIN_GRAY_RANGE && global_best<=MAX_ERROR &&
                           ({1'b0,global_best}+MIN_MARGIN)<={1'b0,global_second}) begin
                            if(previous_class==winning_class) begin
                                if(streak<CONFIRM_FRAMES) streak<=streak+1'b1;
                                matched<=streak>=CONFIRM_FRAMES-1;
                                class_id<=streak>=CONFIRM_FRAMES-1 ? winning_class:3'd0;
                            end else begin
                                streak<=1;previous_class<=winning_class;
                                matched<=CONFIRM_FRAMES<=1;class_id<=CONFIRM_FRAMES<=1 ? winning_class:3'd0;
                            end
                        end else begin matched<=0;class_id<=0;previous_class<=0;streak<=0;end
                    end
                    default:state<=IDLE;
                endcase
            end
        end
    end
endmodule
