// Pure-video TMDS compatibility path. No HDMI data islands or audio packets.
module capture_tmds_channel(
    input wire clk, rst, de,
    input wire [7:0] data,
    input wire [1:0] control,
    output reg [9:0] symbol
);
    integer n, ones, balance;
    reg [8:0] q;
    reg use_xnor;
    reg signed [5:0] disparity = 0;
    always @* begin
        ones = 0;
        for (n=0;n<8;n=n+1) ones = ones + data[n];
        use_xnor = (ones > 4) || ((ones == 4) && !data[0]);
        q[0] = data[0];
        for (n=1;n<8;n=n+1)
            q[n] = use_xnor ? ~(q[n-1] ^ data[n]) : (q[n-1] ^ data[n]);
        q[8] = !use_xnor;
        ones = 0;
        for (n=0;n<8;n=n+1) ones = ones + q[n];
        balance = 2*ones-8;
    end
    always @(posedge clk) begin
        if (rst || !de) begin
            disparity <= 0;
            case (rst ? 2'b00 : control)
                2'b00: symbol <= 10'b1101010100;
                2'b01: symbol <= 10'b0010101011;
                2'b10: symbol <= 10'b0101010100;
                2'b11: symbol <= 10'b1010101011;
            endcase
        end else if ((disparity == 0) || (balance == 0)) begin
            symbol <= {~q[8],q[8],q[8] ? q[7:0] : ~q[7:0]};
            disparity <= disparity + (q[8] ? balance : -balance);
        end else if (((disparity > 0) && (balance > 0)) ||
                     ((disparity < 0) && (balance < 0))) begin
            symbol <= {1'b1,q[8],~q[7:0]};
            disparity <= disparity + (q[8] ? 2 : 0) - balance;
        end else begin
            symbol <= {1'b0,q[8],q[7:0]};
            disparity <= disparity - (q[8] ? 0 : 2) + balance;
        end
    end
endmodule

module capture_dvi_compat(
    input wire pixelclk, rst_p,
    input wire [7:0] i_bdata,i_gdata,i_rdata,
    input wire i_hs,i_vs,i_de,
    input wire [1:0] video_format,
    input wire [6:0] video_VIC,
    input wire [23:0] audio_L,audio_R,
    input wire audio_valid,
    input wire [19:0] audio_N,audio_CTS,
    input wire [3:0] audio_sample_frequency,audio_word_length,
    output wire [9:0] tmds_data0,tmds_data1,tmds_data2,tmds_clk
);
    // Isolate the existing overlay mux from the TMDS XOR/decision network.
    // Delay all video timing with RGB so the active window stays aligned.
    reg [23:0] rgb_q;
    reg de_q,hs_q,vs_q;
    always @(posedge pixelclk) begin
        if(rst_p) begin
            rgb_q<=0; de_q<=0; hs_q<=0; vs_q<=0;
        end else begin
            rgb_q<={i_rdata,i_gdata,i_bdata};
            de_q<=i_de; hs_q<=i_hs; vs_q<=i_vs;
        end
    end
    capture_tmds_channel b(pixelclk,rst_p,de_q,rgb_q[7:0],{vs_q,hs_q},tmds_data0);
    capture_tmds_channel g(pixelclk,rst_p,de_q,rgb_q[15:8],2'b00,tmds_data1);
    capture_tmds_channel r(pixelclk,rst_p,de_q,rgb_q[23:16],2'b00,tmds_data2);
    assign tmds_clk = 10'b1111100000;
endmodule
