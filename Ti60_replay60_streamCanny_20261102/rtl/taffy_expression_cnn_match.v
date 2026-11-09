// Fixed centered guide. 16x8 area averaging produces a 32x32 grayscale input.
// Camera/display continue while the folded engine runs; incomplete frames are discarded.
module taffy_expression_cnn_match #(
    parameter integer ROI_X=704,ROI_Y=412,
    parameter integer STEP_X_LOG2=4,STEP_Y_LOG2=3,
    parameter integer CONFIRM_FRAMES=3
)(input clk,rst_n,enable,de,vs,
   input [11:0] x,y,input [7:0] gray,
   output reg matched,output reg result_valid,output busy,
   output signed [31:0] logit0,logit1,logit2,logit3,logit4, output reg [2:0] class_id);
    localparam integer SX=1<<STEP_X_LOG2,SY=1<<STEP_Y_LOG2;
    localparam integer SUM_BITS=8+STEP_X_LOG2+STEP_Y_LOG2;
    wire [11:0] dx=x-ROI_X,dy=y-ROI_Y;
    wire inside_roi=x>=ROI_X && x<ROI_X+32*SX && y>=ROI_Y && y<ROI_Y+32*SY;
    wire [4:0] col=dx>>STEP_X_LOG2;
    wire [4:0] row=dy>>STEP_Y_LOG2;
    wire cell_end=((dx&(SX-1))==SX-1)&&((dy&(SY-1))==SY-1);
    reg [SUM_BITS-1:0] sums[0:31];
    wire [SUM_BITS:0] sum_next={1'b0,sums[col]}+gray;
    wire [SUM_BITS:0] sum_rounded=sum_next+(1<<(STEP_X_LOG2+STEP_Y_LOG2-1));
    reg previous_vs,capturing,malformed;
    reg [10:0] count;
    reg sample_valid,start;
    reg [9:0] sample_index;
    reg [7:0] sample_data,minimum,maximum;
    wire done,target,core_valid;
    wire [2:0] core_class;
    reg [2:0] candidate_class;
    reg [7:0] positive_streak;
    wire core_reset_n=rst_n && enable;
    taffy_expression_cnn_core u_core(.clk(clk),.rst_n(core_reset_n),
        .sample_valid(sample_valid),.sample_index(sample_index),.sample_data(sample_data),
        .start(start),.input_min(minimum),.input_max(maximum),
        .busy(busy),.done(done),.target(target),.valid_result(core_valid),.logit0(logit0),.logit1(logit1),.logit2(logit2),.logit3(logit3),.logit4(logit4),.class_id(core_class),
        .feature_valid(),.feature_layer(),.feature_address(),.feature_value());
    integer i;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            previous_vs<=0;capturing<=0;malformed<=0;count<=0;sample_valid<=0;start<=0;
            sample_index<=0;sample_data<=0;minimum<=255;maximum<=0;
            matched<=0;result_valid<=0;positive_streak<=0;class_id<=0;candidate_class<=0;
            for(i=0;i<32;i=i+1)sums[i]<=0;
        end else begin
            previous_vs<=vs;sample_valid<=0;start<=0;
            if(!enable)begin capturing<=0;count<=0;matched<=0;result_valid<=0;positive_streak<=0;class_id<=0;candidate_class<=0;end
            else begin
                if(done)begin
                    result_valid<=1;
                    if(target && core_class!=0)begin
                        if(core_class!=candidate_class)begin
                            candidate_class<=core_class;positive_streak<=1;
                            matched<=(CONFIRM_FRAMES<=1);class_id<=(CONFIRM_FRAMES<=1) ? core_class:3'd0;
                        end else begin
                            if(positive_streak<CONFIRM_FRAMES)positive_streak<=positive_streak+1'b1;
                            matched<=positive_streak>=CONFIRM_FRAMES-1;
                            class_id<=positive_streak>=CONFIRM_FRAMES-1 ? core_class:3'd0;
                        end
                    end else begin matched<=0;class_id<=0;positive_streak<=0;candidate_class<=0;end
                end
                if(vs && !previous_vs)begin
                    capturing<=!busy && !start;malformed<=0;count<=0;minimum<=255;maximum<=0;
                    if(capturing && count!=0 && count!=1024)begin result_valid<=0;matched<=0;class_id<=0;positive_streak<=0;candidate_class<=0;end
                    for(i=0;i<32;i=i+1)sums[i]<=0;
                end
                if(capturing && de && inside_roi)begin
                    if(cell_end)begin
                        sums[col]<=0;sample_valid<=1;sample_index<={row,col};
                        sample_data<=sum_rounded>>(STEP_X_LOG2+STEP_Y_LOG2);
                        count<=count+1'b1;
                        if({row,col}!=count)malformed<=1;
                    end else sums[col]<=sum_next[SUM_BITS-1:0];
                end
                if(sample_valid)begin
                    if(sample_data<minimum)minimum<=sample_data;
                    if(sample_data>maximum)maximum<=sample_data;
                    if(sample_index==1023)begin
                        capturing<=0;
                        if(count==1024 && !malformed)start<=1;
                        else begin result_valid<=0;matched<=0;class_id<=0;positive_streak<=0;candidate_class<=0;end
                    end
                end
            end
        end
    end
endmodule
