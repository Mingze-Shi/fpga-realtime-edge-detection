// Separable binomial kernel [1 4 6 4 1]^T [1 4 6 4 1] / 256.
// Two window cycles + horizontal sum + vertical sum = four cycles.
module gaussian5x5 #(parameter WIDTH=1920)(
    input clk,rst_n,de_in,vs_in,
    input [11:0] x_in,y_in,
    input [7:0] gray_in,
    output reg de_out,vs_out,
    output reg [11:0] x_out,y_out,
    output reg [8:0] gray_out
);
    wire wd,wv;wire [11:0] wx,wy;wire [199:0] taps;
    canny_window5x5 #(.WIDTH(WIDTH)) window5(
        clk,rst_n,de_in,vs_in,x_in,y_in,gray_in,wd,wv,wx,wy,taps);
    reg [11:0] horizontal[0:4];
    reg hd,hv;reg [11:0] hx,hy;
    integer r;
    wire [15:0] total={4'b0,horizontal[0]}+({4'b0,horizontal[1]}<<2)
        +({4'b0,horizontal[2]}<<2)+({4'b0,horizontal[2]}<<1)
        +({4'b0,horizontal[3]}<<2)+{4'b0,horizontal[4]}+16'd128;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(r=0;r<5;r=r+1)horizontal[r]<=0;
            hd<=0;hv<=0;hx<=0;hy<=0;
            de_out<=0;vs_out<=0;x_out<=0;y_out<=0;gray_out<=0;
        end else begin
            for(r=0;r<5;r=r+1)
                horizontal[r]<={4'b0,taps[(r*5)*8+:8]}
                    +({4'b0,taps[(r*5+1)*8+:8]}<<2)
                    +({4'b0,taps[(r*5+2)*8+:8]}<<2)
                    +({4'b0,taps[(r*5+2)*8+:8]}<<1)
                    +({4'b0,taps[(r*5+3)*8+:8]}<<2)
                    +{4'b0,taps[(r*5+4)*8+:8]};
            hd<=wd;hv<=wv;hx<=wx;hy<=wy;
            de_out<=hd;vs_out<=hv;x_out<=hx;y_out<=hy;
            gray_out<={hx>=4 && hy>=4,total[15:8]};
        end
    end
endmodule
