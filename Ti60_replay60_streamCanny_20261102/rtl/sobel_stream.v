// Camera-independent pixel core. Input coordinates identify the bottom-right
// sample of a causal 3x3 window; gray_out is the matching center sample.
// Four registered stages, including synchronous block-RAM reads.
module sobel_stream #(parameter WIDTH=640)(
    input clk, input rst_n,
    input de_in, input hs_in, input vs_in,
    input [11:0] x_in, input [11:0] y_in,
    input [7:0] gray_in, input [10:0] threshold,
    output reg de_out, output reg hs_out, output reg vs_out,
    output reg [11:0] x_out, output reg [11:0] y_out,
    output reg [7:0] gray_out, output reg [7:0] edge_out,
    output reg [7:0] binary_out
);
    reg [7:0] line_even[0:WIDTH-1];
    reg [7:0] line_odd[0:WIDTH-1];
    reg [7:0] q_even,q_odd,pixel_s1;
    reg [11:0] x_s1,y_s1;
    reg de_s1,hs_s1,vs_s1;
    // No reset on RAM contents: first two rows are masked instead.
    always @(posedge clk) if(de_in) begin
        q_even <= line_even[x_in];
        q_odd <= line_odd[x_in];
        if(y_in[0]) line_odd[x_in] <= gray_in;
        else line_even[x_in] <= gray_in;
    end
    wire [7:0] row_prev = y_s1[0] ? q_even:q_odd;
    wire [7:0] row_prev2 = y_s1[0] ? q_odd:q_even;
    reg [7:0] a0,a1,b0,b1,c0,c1;
    reg signed [11:0] gx_s2,gy_s2;
    reg [7:0] gray_s2,gray_s3;
    reg [11:0] x_s2,y_s2,x_s3,y_s3;
    reg de_s2,hs_s2,vs_s2,valid_s2;
    reg de_s3,hs_s3,vs_s3,valid_s3;
    reg [10:0] threshold_s1,threshold_s2,threshold_s3;
    reg [11:0] absx_s3,absy_s3;
    wire [12:0] magnitude = {1'b0,absx_s3}+{1'b0,absy_s3};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pixel_s1<=0;x_s1<=0;y_s1<=0;de_s1<=0;hs_s1<=1;vs_s1<=1;
            a0<=0;a1<=0;b0<=0;b1<=0;c0<=0;c1<=0;
            gx_s2<=0;gy_s2<=0;gray_s2<=0;x_s2<=0;y_s2<=0;
            de_s2<=0;hs_s2<=1;vs_s2<=1;valid_s2<=0;
            absx_s3<=0;absy_s3<=0;gray_s3<=0;x_s3<=0;y_s3<=0;
            de_s3<=0;hs_s3<=1;vs_s3<=1;valid_s3<=0;
            threshold_s1<=0;threshold_s2<=0;threshold_s3<=0;
            de_out<=0;hs_out<=1;vs_out<=1;gray_out<=0;edge_out<=0;
            binary_out<=0;x_out<=0;y_out<=0;
        end else begin
            pixel_s1<=gray_in;x_s1<=x_in;y_s1<=y_in;
            de_s1<=de_in;hs_s1<=hs_in;vs_s1<=vs_in;threshold_s1<=threshold;
            if(de_s1) begin
                if(x_s1==0) begin
                    a0<=0;a1<=row_prev2;b0<=0;b1<=row_prev;c0<=0;c1<=pixel_s1;
                end else begin
                    a0<=a1;a1<=row_prev2;b0<=b1;b1<=row_prev;c0<=c1;c1<=pixel_s1;
                end
                gx_s2 <= $signed({4'b0,row_prev2}) + ($signed({4'b0,row_prev})<<<1)
                         + $signed({4'b0,pixel_s1}) - $signed({4'b0,a0})
                         - ($signed({4'b0,b0})<<<1) - $signed({4'b0,c0});
                gy_s2 <= $signed({4'b0,c0}) + ($signed({4'b0,c1})<<<1)
                         + $signed({4'b0,pixel_s1}) - $signed({4'b0,a0})
                         - ($signed({4'b0,a1})<<<1) - $signed({4'b0,row_prev2});
            end
            gray_s2<=b1;x_s2<=x_s1;y_s2<=y_s1;
            de_s2<=de_s1;hs_s2<=hs_s1;vs_s2<=vs_s1;
            valid_s2<=de_s1 && x_s1>=2 && y_s1>=2;threshold_s2<=threshold_s1;
            absx_s3<=gx_s2[11] ? -gx_s2:gx_s2;
            absy_s3<=gy_s2[11] ? -gy_s2:gy_s2;
            gray_s3<=gray_s2;x_s3<=x_s2;y_s3<=y_s2;
            de_s3<=de_s2;hs_s3<=hs_s2;vs_s3<=vs_s2;valid_s3<=valid_s2;
            threshold_s3<=threshold_s2;
            de_out<=de_s3;hs_out<=hs_s3;vs_out<=vs_s3;x_out<=x_s3;y_out<=y_s3;
            gray_out<=valid_s3 ? gray_s3:0;
            edge_out<=valid_s3 ? (magnitude>255 ? 8'hff:magnitude[7:0]):0;
            binary_out<=valid_s3 && magnitude>=threshold_s3 ? 8'hff:0;
        end
    end
endmodule
