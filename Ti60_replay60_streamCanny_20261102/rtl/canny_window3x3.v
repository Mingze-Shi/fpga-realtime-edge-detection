// Two-cycle causal window. RAM is not reset; consumers mask incomplete windows.
module canny_window3x3 #(parameter WIDTH=480, BITS=8)(
    input clk, rst_n, de_in, vs_in,
    input [11:0] x_in, y_in,
    input [BITS-1:0] data_in,
    output reg de_out, vs_out,
    output reg [11:0] x_out, y_out,
    output reg [BITS-1:0] p00,p01,p02,p10,p11,p12,p20,p21,p22
);
    reg [BITS-1:0] even_line[0:WIDTH-1], odd_line[0:WIDTH-1];
    reg [BITS-1:0] qe,qo,d1,a0,a1,b0,b1,c0,c1;
    reg [11:0] x1,y1;
    reg de1,vs1;
    always @(posedge clk) if(de_in && x_in<WIDTH) begin
        qe<=even_line[x_in]; qo<=odd_line[x_in];
        if(y_in[0]) odd_line[x_in]<=data_in;
        else even_line[x_in]<=data_in;
    end
    wire [BITS-1:0] up=y1[0] ? qe:qo;
    wire [BITS-1:0] up2=y1[0] ? qo:qe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            d1<=0;x1<=0;y1<=0;de1<=0;vs1<=0;
            a0<=0;a1<=0;b0<=0;b1<=0;c0<=0;c1<=0;
            de_out<=0;vs_out<=0;x_out<=0;y_out<=0;
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;
            p20<=0;p21<=0;p22<=0;
        end else begin
            d1<=data_in;x1<=x_in;y1<=y_in;de1<=de_in;vs1<=vs_in;
            de_out<=de1;vs_out<=vs1;x_out<=x1;y_out<=y1;
            if(de1) begin
                a0<=x1==0 ? 0:a1; a1<=up2;
                b0<=x1==0 ? 0:b1; b1<=up;
                c0<=x1==0 ? 0:c1; c1<=d1;
                p00<=a0;p01<=a1;p02<=up2;
                p10<=b0;p11<=b1;p12<=up;
                p20<=c0;p21<=c1;p22<=d1;
            end
        end
    end
endmodule
