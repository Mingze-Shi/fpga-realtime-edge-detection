// Folded int8 CNN. Shared convolution MAC and two 1024-byte activation memories.
// Pooling is fused into convolution traversal; full 32x32x4 maps are never stored.
module taffy_expression_cnn_core #(
    parameter integer NORMALIZE=1,
    parameter WEIGHT_FILE="assets/cnn_expression/weights.hex"
)(
    input clk,rst_n,
    input sample_valid, input [9:0] sample_index, input [7:0] sample_data,
    input start, input [7:0] input_min,input_max,
    output reg busy, output reg done,
    output reg target, output reg valid_result,
    output reg signed [31:0] logit0,logit1,logit2,logit3,logit4,
    output [2:0] class_id,
    output feature_valid, output [1:0] feature_layer,
    output [9:0] feature_address, output [7:0] feature_value
);
`include "rtl/cnn_expression_params.vh"
    localparam IDLE=0, N_ADDR=1,N_WAIT=2,N_SET=3,N_DIV=4,N_WRITE=5,
        LAYER=6,PIXEL=7,TAP_ADDR=8,TAP_WAIT=9,TAP_PRODUCT=10,TAP_ACC=11,
        QUANT=12,COMMIT=13,FC_INIT=14,FC_ADDR=15,FC_WAIT=16,
        FC_PRODUCT=17,FC_ACC=18,FC_END=19,FINISH=20,DECIDE=21;
    reg [4:0] state;
    reg [7:0] ram_a[0:1023],ram_b[0:1023];
    reg signed [7:0] weights[0:1023];
    initial $readmemh(WEIGHT_FILE,weights);
    reg [9:0] rd_address,weight_address;
    reg [7:0] aq,bq; reg signed [7:0] wq;
    reg [1:0] layer;
    reg [3:0] oc,ic,ox,oy;
    reg [1:0] sub,kx,ky;
    reg tap_inside;
    reg signed [31:0] accumulator;
    reg signed [17:0] product;
    reg [7:0] quantized,pool_max;
    reg [15:0] global_sum;
    reg [7:0] average[0:7];
    reg [2:0] fc_class;
    reg [9:0] norm_index;
    reg [7:0] norm_min,norm_span;
    reg [15:0] dividend,quotient;
    reg [8:0] remainder;
    reg [4:0] div_count;
    wire [8:0] trial={remainder[7:0],dividend[15]};
    wire [7:0] norm_delta=aq-norm_min;
    wire [15:0] norm_numerator={norm_delta,8'd0}-{8'd0,norm_delta}+{9'd0,norm_span[7:1]};
    wire signed [7:0] ix=layer==2 ? $signed({4'd0,ox})+$signed({6'd0,kx})-8'sd1 :
        $signed({3'd0,ox,1'b0})+$signed({7'd0,sub[0]})+$signed({6'd0,kx})-8'sd1;
    wire signed [7:0] iy=layer==2 ? $signed({4'd0,oy})+$signed({6'd0,ky})-8'sd1 :
        $signed({3'd0,oy,1'b0})+$signed({7'd0,sub[1]})+$signed({6'd0,ky})-8'sd1;
    wire inside_tap=ix>=0 && iy>=0 && ix<(layer==0 ? 32:layer==1 ? 16:8) && iy<(layer==0 ? 32:layer==1 ? 16:8);
    wire [9:0] tap_address=layer==0 ? {iy[4:0],ix[4:0]} :
        layer==1 ? {ic[1:0],iy[3:0],ix[3:0]} : {1'b0,ic[2:0],iy[2:0],ix[2:0]};
    wire [9:0] dst_address=layer==0 ? {oc[1:0],oy[3:0],ox[3:0]} :
        {1'b0,oc[2:0],oy[2:0],ox[2:0]};
    wire [9:0] conv3_address={1'b0,oc[2:0],oy[2:0],ox[2:0]};
    wire [9:0] weight_base=layer==0 ? (oc*10'd9) : layer==1 ? 10'd36+oc*10'd36 : 10'd324+oc*10'd72;
    wire [7:0] pooled=quantized>pool_max ? quantized:pool_max;
    wire [15:0] sum_next=global_sum+{8'd0,quantized};
    wire [15:0] sum_rounded=sum_next+16'd32;
    wire signed [31:0] rounded1=accumulator+(32'sd1<<(CNN_SHIFT1-1));
    wire signed [31:0] rounded2=accumulator+(32'sd1<<(CNN_SHIFT2-1));
    wire signed [31:0] rounded3=accumulator+(32'sd1<<(CNN_SHIFT3-1));
    wire signed [31:0] scaled=layer==0 ? (rounded1>>>CNN_SHIFT1) : layer==1 ? (rounded2>>>CNN_SHIFT2):(rounded3>>>CNN_SHIFT3);
    wire [7:0] clipped=scaled<0 ? 8'd0:scaled>255 ? 8'd255:scaled[7:0];
    wire [7:0] activation=tap_inside ? (layer==1 ? bq:aq):8'd0;
    wire signed [8:0] signed_activation=$signed({1'b0,activation});
    wire a_write=(!busy && sample_valid) || state==N_WRITE || (state==COMMIT && layer==1 && sub==3);
    wire [9:0] a_waddr=state==N_WRITE ? norm_index : busy ? dst_address:sample_index;
    wire [7:0] a_wdata=state==N_WRITE ? quotient[7:0] : busy ? pooled:sample_data;
    wire b_write=state==COMMIT && layer==0 && sub==3;
    always @(posedge clk) begin
        aq<=ram_a[rd_address];bq<=ram_b[rd_address];wq<=weights[weight_address];
        if(a_write)ram_a[a_waddr]<=a_wdata;
        if(b_write)ram_b[dst_address]<=pooled;
    end
    assign feature_valid=state==COMMIT && (layer==2 || sub==3);
    assign feature_layer=layer;
    assign feature_address=layer==2 ? conv3_address:dst_address;
    assign feature_value=layer==2 ? quantized:pooled;
    wire decision_accept,decision_busy,decision_done;
    expression_cnn_decision_seq u_decision(.clk(clk),.rst_n(rst_n),.start(state==DECIDE && !decision_busy && !decision_done),.busy(decision_busy),.done(decision_done),.logit0(logit0),.logit1(logit1),.logit2(logit2),.logit3(logit3),.logit4(logit4),
        .class_id(class_id),.accepted(decision_accept),.probability_pass(),.margin_pass());
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;busy<=0;done<=0;target<=0;valid_result<=0;
            logit0<=0;logit1<=0;logit2<=0;logit3<=0;logit4<=0;rd_address<=0;weight_address<=0;
            layer<=0;oc<=0;ic<=0;ox<=0;oy<=0;sub<=0;kx<=0;ky<=0;tap_inside<=0;
            accumulator<=0;product<=0;quantized<=0;pool_max<=0;global_sum<=0;
            norm_index<=0;norm_min<=0;norm_span<=0;dividend<=0;quotient<=0;remainder<=0;div_count<=0;fc_class<=0;
            for(i=0;i<8;i=i+1)average[i]<=0;
        end else begin
            done<=0;
            case(state)
            IDLE: if(start) begin
                busy<=1;norm_index<=0;norm_min<=input_min;norm_span<=input_max-input_min;
                layer<=0;
                if(NORMALIZE && input_max-input_min<16)begin
                    target<=0;logit0<=0;logit1<=-1;logit2<=-1;logit3<=-1;logit4<=-1;state<=FINISH;
                end else state<=NORMALIZE ? N_ADDR:LAYER;
            end
            N_ADDR:begin rd_address<=norm_index;state<=N_WAIT;end
            N_WAIT:state<=N_SET;
            N_SET:begin dividend<=norm_numerator;quotient<=0;remainder<=0;div_count<=0;state<=N_DIV;end
            N_DIV:begin
                dividend<={dividend[14:0],1'b0};
                if(trial>={1'b0,norm_span})begin remainder<=trial-{1'b0,norm_span};quotient<={quotient[14:0],1'b1};end
                else begin remainder<=trial;quotient<={quotient[14:0],1'b0};end
                if(div_count==15)state<=N_WRITE;else div_count<=div_count+1'b1;
            end
            N_WRITE:if(norm_index==1023)state<=LAYER;else begin norm_index<=norm_index+1'b1;state<=N_ADDR;end
            LAYER:begin oc<=0;ox<=0;oy<=0;sub<=0;pool_max<=0;global_sum<=0;state<=PIXEL;end
            PIXEL:begin
                ic<=0;kx<=0;ky<=0;weight_address<=weight_base;
                accumulator<=expression_bias(layer,oc);state<=TAP_ADDR;
            end
            TAP_ADDR:begin rd_address<=tap_address;tap_inside<=inside_tap;state<=TAP_WAIT;end
            TAP_WAIT:state<=TAP_PRODUCT;
            TAP_PRODUCT:begin product<=signed_activation*wq;state<=TAP_ACC;end
            TAP_ACC:begin
                accumulator<=accumulator+product;
                weight_address<=weight_address+1'b1;
                if(kx==2)begin
                    kx<=0;
                    if(ky==2)begin
                        ky<=0;
                        if(ic==(layer==0 ? 0:layer==1 ? 3:7))state<=QUANT;
                        else begin ic<=ic+1'b1;state<=TAP_ADDR;end
                    end else begin ky<=ky+1'b1;state<=TAP_ADDR;end
                end else begin kx<=kx+1'b1;state<=TAP_ADDR;end
            end
            QUANT:begin quantized<=clipped;state<=COMMIT;end
            COMMIT:begin
                if(layer!=2 && sub!=3)begin pool_max<=pooled;sub<=sub+1'b1;state<=PIXEL;end
                else begin
                    sub<=0;pool_max<=0;
                    if(layer==2)global_sum<=sum_next;
                    if(ox==(layer==0 ? 15:7))begin
                        ox<=0;
                        if(oy==(layer==0 ? 15:7))begin
                            oy<=0;global_sum<=0;
                            if(layer==2)average[oc[2:0]]<=sum_rounded[13:6];
                            if(oc==(layer==0 ? 3:7))begin
                                if(layer==2)begin fc_class<=0;state<=FC_INIT;end
                                else begin layer<=layer+1'b1;state<=LAYER;end
                            end else begin oc<=oc+1'b1;state<=PIXEL;end
                        end else begin oy<=oy+1'b1;state<=PIXEL;end
                    end else begin ox<=ox+1'b1;state<=PIXEL;end
                end
            end
            FC_INIT:begin ic<=0;accumulator<=expression_bias(2'd3,{1'd0,fc_class});state<=FC_ADDR;end
            FC_ADDR:begin weight_address<=10'd900+{4'd0,fc_class,3'd0}+{6'd0,ic};state<=FC_WAIT;end
            FC_WAIT:state<=FC_PRODUCT;
            FC_PRODUCT:begin product<=$signed({1'b0,average[ic[2:0]]})*wq;state<=FC_ACC;end
            FC_ACC:begin accumulator<=accumulator+product;if(ic==7)state<=FC_END;else begin ic<=ic+1'b1;state<=FC_ADDR;end end
            FC_END:begin
                case(fc_class)
                  0:logit0<=(accumulator <<< CNN_LOGIT_LEFT_SHIFT);1:logit1<=(accumulator <<< CNN_LOGIT_LEFT_SHIFT);2:logit2<=(accumulator <<< CNN_LOGIT_LEFT_SHIFT);
                  3:logit3<=(accumulator <<< CNN_LOGIT_LEFT_SHIFT);4:logit4<=(accumulator <<< CNN_LOGIT_LEFT_SHIFT);
                endcase
                if(fc_class==4)state<=DECIDE;
                else begin fc_class<=fc_class+1'b1;state<=FC_INIT;end
            end
            DECIDE:if(decision_done)begin target<=decision_accept;state<=FINISH;end
            FINISH:begin busy<=0;done<=1;valid_result<=1;state<=IDLE;end
            default:begin state<=IDLE;busy<=0;end
            endcase
        end
    end
endmodule
