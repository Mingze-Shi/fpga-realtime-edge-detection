// Free-running CTA 1080p60 raster at 148.5 MHz, independent of camera FIFO.
module capture_test_pattern(
    input wire clk, rst_n,
    output reg hs,vs,de,
    output reg [7:0] red,green,blue
);
    reg [11:0] x=0;
    reg [10:0] y=0;
    reg [23:0] color;
    always @* begin
        if(x<432) color=24'hffffff;
        else if(x<672) color=24'hffff00;
        else if(x<912) color=24'h00ffff;
        else if(x<1152) color=24'h00ff00;
        else if(x<1392) color=24'hff00ff;
        else if(x<1632) color=24'hff0000;
        else if(x<1872) color=24'h0000ff;
        else color=24'h202020;
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            x<=0;y<=0;hs<=0;vs<=0;de<=0;
            red<=0;green<=0;blue<=0;
        end else begin
            if(x==2199) begin
                x<=0;
                if(y==1124)y<=0;else y<=y+1'b1;
            end else x<=x+1'b1;
            hs<=(x<44); vs<=(y<5);
            de<=(x>=192 && x<2112 && y>=41 && y<1121);
            {red,green,blue}<=color;
        end
    end
endmodule
