// Two-cycle causal 5x5 window. Four RAM banks rotate by row modulo four.
// taps[(row*5+column)*BITS +: BITS], oldest row/column first.
module canny_window5x5 #(parameter WIDTH=1920,BITS=8)(
    input clk,rst_n,de_in,vs_in,
    input [11:0] x_in,y_in,
    input [BITS-1:0] data_in,
    output reg de_out,vs_out,
    output reg [11:0] x_out,y_out,
    output reg [25*BITS-1:0] taps
);
    reg [BITS-1:0] bank0[0:WIDTH-1],bank1[0:WIDTH-1];
    reg [BITS-1:0] bank2[0:WIDTH-1],bank3[0:WIDTH-1];
    reg [BITS-1:0] q0,q1,q2,q3,d1;
    reg [BITS-1:0] rows[0:4];
    reg [BITS-1:0] history[0:19];
    reg [11:0] x1,y1;
    reg de1,vs1;
    integer r,c;
    always @(posedge clk) if(de_in && x_in<WIDTH) begin
        q0<=bank0[x_in];q1<=bank1[x_in];
        q2<=bank2[x_in];q3<=bank3[x_in];
        case(y_in[1:0])
            0:bank0[x_in]<=data_in;
            1:bank1[x_in]<=data_in;
            2:bank2[x_in]<=data_in;
            3:bank3[x_in]<=data_in;
        endcase
    end
    always @* begin
        case(y1[1:0])
            0:begin rows[0]=q0;rows[1]=q1;rows[2]=q2;rows[3]=q3;end
            1:begin rows[0]=q1;rows[1]=q2;rows[2]=q3;rows[3]=q0;end
            2:begin rows[0]=q2;rows[1]=q3;rows[2]=q0;rows[3]=q1;end
            3:begin rows[0]=q3;rows[1]=q0;rows[2]=q1;rows[3]=q2;end
        endcase
        rows[4]=d1;
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            d1<=0;x1<=0;y1<=0;de1<=0;vs1<=0;
            de_out<=0;vs_out<=0;x_out<=0;y_out<=0;taps<=0;
            for(r=0;r<20;r=r+1) history[r]<=0;
        end else begin
            d1<=data_in;x1<=x_in;y1<=y_in;de1<=de_in;vs1<=vs_in;
            de_out<=de1;vs_out<=vs1;x_out<=x1;y_out<=y1;
            if(de1) for(r=0;r<5;r=r+1) begin
                for(c=0;c<4;c=c+1) begin
                    taps[(r*5+c)*BITS+:BITS]<=x1>=4-c ? history[r*4+c]:{BITS{1'b0}};
                    if(c<3) history[r*4+c]<=x1==0 ? 0:history[r*4+c+1];
                end
                history[r*4+3]<=rows[r];
                taps[(r*5+4)*BITS+:BITS]<=rows[r];
            end
        end
    end
endmodule
