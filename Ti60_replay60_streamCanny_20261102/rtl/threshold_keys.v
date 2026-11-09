// Active-low board keys. One event per debounced press; hold does not repeat.
module threshold_keys #(
    parameter integer DEBOUNCE_CYCLES = 2970000,
    parameter integer SUPPRESS_ENABLE = 0,
    parameter [10:0] INITIAL_THRESHOLD = 11'd32,
    parameter [10:0] MIN_THRESHOLD = 11'd16,
    parameter [10:0] MAX_THRESHOLD = 11'd2032,
    parameter [10:0] STEP = 11'd8
)(
    input clk, input rst_n,
    input increase_n, input decrease_n,
    input suppress_adjust,
    output up_event,down_event,
    output reg [10:0] threshold_requested
);
    localparam integer COUNTER_BITS = DEBOUNCE_CYCLES > 1 ? $clog2(DEBOUNCE_CYCLES) : 1;
    (* async_reg = "true", syn_preserve = 1 *) reg [1:0] key_meta, key_sync;
    reg [1:0] stable_n;
    reg [1:0] press;
    assign up_event=press==2'b01;
    assign down_event=press==2'b10;
    reg [COUNTER_BITS-1:0] count_up, count_down;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 2'b11; key_sync <= 2'b11;
            stable_n <= 2'b11; press <= 0;
            count_up <= 0; count_down <= 0;
            threshold_requested <= INITIAL_THRESHOLD;
        end else begin
            key_meta <= {decrease_n, increase_n};
            key_sync <= key_meta;
            press <= 0;
            if (key_sync[0] == stable_n[0]) count_up <= 0;
            else if (count_up == DEBOUNCE_CYCLES-1) begin
                count_up <= 0; stable_n[0] <= key_sync[0];
                if (!key_sync[0]) press[0] <= 1;
            end else count_up <= count_up + 1'b1;
            if (key_sync[1] == stable_n[1]) count_down <= 0;
            else if (count_down == DEBOUNCE_CYCLES-1) begin
                count_down <= 0; stable_n[1] <= key_sync[1];
                if (!key_sync[1]) press[1] <= 1;
            end else count_down <= count_down + 1'b1;
            // Simultaneous events cancel; arithmetic saturates without wrapping.
            if ((!SUPPRESS_ENABLE || !suppress_adjust) && press == 2'b01) begin
                if (threshold_requested <= MAX_THRESHOLD-STEP)
                    threshold_requested <= threshold_requested + STEP;
                else threshold_requested <= MAX_THRESHOLD;
            end else if ((!SUPPRESS_ENABLE || !suppress_adjust) && press == 2'b10) begin
                if (threshold_requested >= MIN_THRESHOLD+STEP)
                    threshold_requested <= threshold_requested - STEP;
                else threshold_requested <= MIN_THRESHOLD;
            end
        end
    end
endmodule
