// Exact 25-sample median, not a median of row medians.
// 32-way bitonic network (seven 255 sentinels), one compare per pipeline stage.
// Latency: window 2 + sorting 15 + output 1 = 18 clocks, one pixel/clock.
module median5x5 #(parameter WIDTH=1920)(
    input clk,rst_n,de_in,hs_in,vs_in,
    input [11:0] x_in,y_in,
    input [7:0] gray_in,
    output reg de_out,hs_out,vs_out,
    output reg [11:0] x_out,y_out,
    output reg [7:0] gray_out
);
    wire wd,wv;wire [11:0] wx,wy;wire [199:0] taps;
    canny_window5x5 #(.WIDTH(WIDTH)) window5(
        clk,rst_n,de_in,vs_in,x_in,y_in,gray_in,wd,wv,wx,wy,taps);
    wire [255:0] values[0:15];
    wire [34:0] metadata[0:15];
    assign values[0]={{56{1'b1}},taps};
    assign metadata[0]={wx>=4 && wy>=4,wv,wd,wx,wy,taps[192+:8]};
    genvar k,j,i;
    generate for(k=1;k<=5;k=k+1) begin: size
        for(j=0;j<k;j=j+1) begin: distance
            localparam S=k*(k-1)/2+j;
            localparam D=1<<(k-1-j);
            reg [255:0] sorted;
            reg [34:0] delayed;
            for(i=0;i<32;i=i+1) begin: compare
                localparam P=i^D;
                localparam TAKE_MIN=((i & (1<<k))==0)==(i<P);
                wire [7:0] a=values[S][i*8+:8];
                wire [7:0] b=values[S][P*8+:8];
                always @(posedge clk or negedge rst_n)
                    if(!rst_n) sorted[i*8+:8]<=0;
                    else sorted[i*8+:8]<=TAKE_MIN ? ((a<b)?a:b):((a>b)?a:b);
            end
            always @(posedge clk or negedge rst_n)
                if(!rst_n) delayed<=0;else delayed<=metadata[S];
            assign values[S+1]=sorted;
            assign metadata[S+1]=delayed;
        end
    end endgenerate
    reg [16:0] hs_pipe;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            hs_pipe<=0;de_out<=0;hs_out<=0;vs_out<=0;
            x_out<=0;y_out<=0;gray_out<=0;
        end else begin
            hs_pipe<={hs_pipe[15:0],hs_in};hs_out<=hs_pipe[16];
            {vs_out,de_out,x_out,y_out}<=metadata[15][33:8];
            gray_out<=metadata[15][34] ? values[15][12*8+:8]:metadata[15][7:0];
        end
    end
endmodule
