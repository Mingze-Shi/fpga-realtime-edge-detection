// Traditional Canny front end: Gaussian -> Sobel -> four-direction NMS
// -> dual threshold. Magnitude squared avoids sqrt without changing ordering.
// class_out: 0=background, 1=weak, 2=strong.
// Latency: 10 clocks (3x3) or 11 clocks (GAUSSIAN5).
// Coordinates are causal; kernel centres are 3 or 4 pixels/rows behind labels.
module canny_frontend #(parameter WIDTH=480, GAUSSIAN5=0)(
    input clk,rst_n,de_in,vs_in,
    input [11:0] x_in,y_in,
    input [7:0] gray_in,
    input [10:0] high_threshold,
    output reg de_out,vs_out,
    output reg [11:0] x_out,y_out,
    output reg [1:0] class_out
);
    wire gd,gv;wire [11:0] gx,gy;
    wire [7:0] g00,g01,g02,g10,g11,g12,g20,g21,g22;
    canny_window3x3 #(.WIDTH(WIDTH)) gaussian_window(
        .clk(clk),.rst_n(rst_n),.de_in(de_in),.vs_in(vs_in),
        .x_in(x_in),.y_in(y_in),.data_in(gray_in),
        .de_out(gd),.vs_out(gv),.x_out(gx),.y_out(gy),
        .p00(g00),.p01(g01),.p02(g02),.p10(g10),.p11(g11),.p12(g12),
        .p20(g20),.p21(g21),.p22(g22));
    wire [11:0] gaussian_sum={4'b0,g00}+({4'b0,g01}<<1)+{4'b0,g02}
        +({4'b0,g10}<<1)+({4'b0,g11}<<2)+({4'b0,g12}<<1)
        +{4'b0,g20}+({4'b0,g21}<<1)+{4'b0,g22}+12'd8;
    wire [8:0] gaussian;
    wire sd,sv;wire [11:0] sx,sy;
    generate if(GAUSSIAN5) begin: gaussian_5x5
        gaussian5x5 #(.WIDTH(WIDTH)) filter5(
            clk,rst_n,de_in,vs_in,x_in,y_in,gray_in,sd,sv,sx,sy,gaussian);
    end else begin: gaussian_3x3
        reg [8:0] value;
        reg d,v;reg [11:0] x,y;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin value<=0;d<=0;v<=0;x<=0;y<=0;end
            else begin
                value<={gx>=2 && gy>=2,gaussian_sum[11:4]};
                d<=gd;v<=gv;x<=gx;y<=gy;
            end
        end
        assign gaussian=value;assign sd=d;assign sv=v;assign sx=x;assign sy=y;
    end endgenerate
    wire wd,wv;wire [11:0] wx,wy;
    wire [8:0] s00,s01,s02,s10,s11,s12,s20,s21,s22;
    canny_window3x3 #(.WIDTH(WIDTH),.BITS(9)) sobel_window(
        .clk(clk),.rst_n(rst_n),.de_in(sd),.vs_in(sv),
        .x_in(sx),.y_in(sy),.data_in(gaussian),
        .de_out(wd),.vs_out(wv),.x_out(wx),.y_out(wy),
        .p00(s00),.p01(s01),.p02(s02),.p10(s10),.p11(s11),.p12(s12),
        .p20(s20),.p21(s21),.p22(s22));
    reg signed [11:0] dx,dy;
    reg dd,dv,valid_d;reg [11:0] xx,yy;
    wire [11:0] ax=dx[11] ? -dx:dx;
    wire [11:0] ay=dy[11] ? -dy:dy;
    wire [23:0] square_x=ax*ax, square_y=ay*ay;
    wire [24:0] square_sum={1'b0,square_x}+{1'b0,square_y};
    // tan(22.5 deg) ~= 106/256. Direction uses image coordinates (y down).
    wire [19:0] ax256={ax,8'b0}, ay256={ay,8'b0};
    wire [19:0] ax106=ax*20'd106, ay106=ay*20'd106;
    wire [1:0] direction=ay256<=ax106 ? 2'd0 :
        (ax256<=ay106 ? 2'd2 : ((dx[11]==dy[11]) ? 2'd1:2'd3));
    reg [23:0] gradient; // valid, direction[1:0], squared magnitude[20:0]
    reg md,mv;reg [11:0] mx,my;
    wire nd,nv;wire [11:0] nx,ny;
    wire [23:0] n00,n01,n02,n10,n11,n12,n20,n21,n22;
    canny_window3x3 #(.WIDTH(WIDTH),.BITS(24)) nms_window(
        .clk(clk),.rst_n(rst_n),.de_in(md),.vs_in(mv),
        .x_in(mx),.y_in(my),.data_in(gradient),
        .de_out(nd),.vs_out(nv),.x_out(nx),.y_out(ny),
        .p00(n00),.p01(n01),.p02(n02),.p10(n10),.p11(n11),.p12(n12),
        .p20(n20),.p21(n21),.p22(n22));
    reg [20:0] before_mag,after_mag;
    always @* begin
        case(n11[22:21])
            0: begin before_mag=n10[20:0];after_mag=n12[20:0];end
            1: begin before_mag=n00[20:0];after_mag=n22[20:0];end
            2: begin before_mag=n01[20:0];after_mag=n21[20:0];end
            default: begin before_mag=n02[20:0];after_mag=n20[20:0];end
        endcase
    end
    wire [10:0] low_threshold=high_threshold>>1;
    wire [21:0] high_squared=high_threshold*high_threshold;
    wire [21:0] low_squared=low_threshold*low_threshold;
    wire nvalid=nx>=(GAUSSIAN5 ? 8:6) && ny>=(GAUSSIAN5 ? 8:6) && n00[23] && n01[23] && n02[23]
        && n10[23] && n11[23] && n12[23] && n20[23] && n21[23] && n22[23];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dx<=0;dy<=0;dd<=0;dv<=0;valid_d<=0;xx<=0;yy<=0;
            gradient<=0;md<=0;mv<=0;mx<=0;my<=0;
            de_out<=0;vs_out<=0;x_out<=0;y_out<=0;class_out<=0;
        end else begin
            dx<=$signed({4'b0,s02[7:0]})+($signed({4'b0,s12[7:0]})<<<1)
                +$signed({4'b0,s22[7:0]})-$signed({4'b0,s00[7:0]})
                -($signed({4'b0,s10[7:0]})<<<1)-$signed({4'b0,s20[7:0]});
            dy<=$signed({4'b0,s20[7:0]})+($signed({4'b0,s21[7:0]})<<<1)
                +$signed({4'b0,s22[7:0]})-$signed({4'b0,s00[7:0]})
                -($signed({4'b0,s01[7:0]})<<<1)-$signed({4'b0,s02[7:0]});
            dd<=wd;dv<=wv;xx<=wx;yy<=wy;
            valid_d<=wx>=(GAUSSIAN5 ? 6:4) && wy>=(GAUSSIAN5 ? 6:4) && s00[8] && s01[8] && s02[8]
                && s10[8] && s11[8] && s12[8] && s20[8] && s21[8] && s22[8];
            gradient<={valid_d,direction,square_sum[20:0]};
            md<=dd;mv<=dv;mx<=xx;my<=yy;
            de_out<=nd;vs_out<=nv;x_out<=nx;y_out<=ny;
            class_out<=0;
            // Asymmetric tie break thins a two-pixel plateau deterministically.
            if(nd && nvalid && n11[20:0]>0 && n11[20:0]>before_mag && n11[20:0]>=after_mag) begin
                if({1'b0,n11[20:0]}>=high_squared) class_out<=2;
                else if({1'b0,n11[20:0]}>=low_squared) class_out<=1;
            end
        end
    end
endmodule
