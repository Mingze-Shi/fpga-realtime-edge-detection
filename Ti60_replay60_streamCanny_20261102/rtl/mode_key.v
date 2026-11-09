// Active-low SW3: short release changes display mode; a long hold freezes/resumes.
// A long press is consumed once, and its release never generates a short press.
module mode_key #(
    parameter integer DEBOUNCE_CYCLES = 2970000,
    parameter integer DISPLAY_MODES = 2,
    parameter integer LONG_PRESS_CYCLES = 148500000
)(
    input clk, input rst_n, input mode_n,
    output reg color_requested,
    output reg [1:0] mode_requested,
    output reg freeze_requested
);
    localparam integer COUNTER_BITS = DEBOUNCE_CYCLES > 1 ? $clog2(DEBOUNCE_CYCLES) : 1;
    localparam integer HOLD_BITS = LONG_PRESS_CYCLES > 1 ? $clog2(LONG_PRESS_CYCLES) : 1;
    (* async_reg = "true", syn_preserve = 1 *) reg key_meta, key_sync;
    reg stable_n;
    reg [COUNTER_BITS-1:0] count;
    reg [HOLD_BITS-1:0] hold_count;
    reg long_consumed;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_meta <= 1; key_sync <= 1; stable_n <= 1;
            count <= 0;
            hold_count <= 0;
            long_consumed <= 1'b0;
            color_requested <= 1'b0;
            mode_requested<=0;
            freeze_requested <= 1'b0;
        end else begin
            key_meta <= mode_n;
            key_sync <= key_meta;
            if (key_sync == stable_n) count <= 0;
            else if (count == DEBOUNCE_CYCLES-1) begin
                count <= 0;
                stable_n <= key_sync;
            end else count <= count + 1'b1;

            // Release acceptance takes precedence over counting another held cycle.
            if ((key_sync != stable_n) && (count == DEBOUNCE_CYCLES-1)) begin
                hold_count <= 0;
                long_consumed <= 1'b0;
                if (key_sync && !long_consumed) begin
                    if(DISPLAY_MODES==4) begin
                        mode_requested<=mode_requested+1'b1;
                        color_requested<=mode_requested==0;
                    end else begin
                        color_requested <= ~color_requested;
                        mode_requested<=color_requested ? 0:1;
                    end
                end
            end else if (!stable_n && !long_consumed) begin
                if (hold_count == LONG_PRESS_CYCLES-1) begin
                    long_consumed <= 1'b1;
                    freeze_requested <= ~freeze_requested;
                end else hold_count <= hold_count + 1'b1;
            end
        end
    end
endmodule
