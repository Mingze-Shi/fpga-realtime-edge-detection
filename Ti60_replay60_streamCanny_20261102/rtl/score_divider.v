// Match score for the OSD: percent = round(100 * 65536 / denominator), clamped to 0..100.
// The decision engine accumulates a Q16 softmax denominator whose ratio to 65536 is the
// top-class probability lower bound. One 24-step restoring division per frame boundary is
// far cheaper than a variable combinational divider and never sits on the video path.
module score_divider(
    input clk, rst_n, start,
    input [19:0] denominator,
    output reg [7:0] percent,
    output reg ready
);
    localparam integer BITS = 24;
    reg running;
    reg [24:0] dividend, quotient;
    reg [20:0] remainder;
    reg [4:0] count;
    wire [19:0] divisor = denominator < 20'd65536 ? 20'd65536 : denominator;
    wire [20:0] trial = {remainder[19:0], dividend[24]};
    wire bit_in = trial >= {1'b0, divisor};
    wire [24:0] quotient_next = {quotient[23:0], bit_in};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running <= 0; ready <= 0; percent <= 0;
            dividend <= 0; quotient <= 0; remainder <= 0; count <= 0;
        end else begin
            ready <= 0;
            if (start) begin
                // Rounding is folded into the dividend, so a truncating divide rounds.
                dividend <= 25'd6553600 + {5'd0, divisor >> 1};
                quotient <= 0; remainder <= 0; count <= BITS; running <= 1;
            end else if (running) begin
                remainder <= bit_in ? trial - {1'b0, divisor} : trial;
                quotient <= quotient_next;
                dividend <= dividend << 1;
                count <= count - 1'b1;
                if (count == 1) begin
                    running <= 0; ready <= 1;
                    percent <= quotient_next > 25'd100 ? 8'd100 : quotient_next[7:0];
                end
            end
        end
    end
endmodule
