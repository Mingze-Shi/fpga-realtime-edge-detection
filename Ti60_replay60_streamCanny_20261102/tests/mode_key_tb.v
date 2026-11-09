`timescale 1ns/1ps
module mode_key_tb;
    localparam integer DEBOUNCE = 4;
    localparam integer HOLD = 20;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, mode_n = 1;
    wire color_requested, freeze_requested;
    mode_key #(.DEBOUNCE_CYCLES(DEBOUNCE), .LONG_PRESS_CYCLES(HOLD)) dut (
        .clk(clk), .rst_n(rst_n), .mode_n(mode_n),
        .color_requested(color_requested), .freeze_requested(freeze_requested)
    );

    integer color_events = 0, freeze_events = 0;
    reg old_color = 0, old_freeze = 0;
    always @(posedge clk) begin
        #1;
        if (!rst_n) begin
            old_color = color_requested;
            old_freeze = freeze_requested;
        end else begin
            if (old_color != color_requested) color_events = color_events + 1;
            if (old_freeze != freeze_requested) freeze_events = freeze_events + 1;
            old_color = color_requested;
            old_freeze = freeze_requested;
        end
    end

    task ticks;
        input integer n;
        integer i;
        begin for (i=0; i<n; i=i+1) begin @(posedge clk); #2; end end
    endtask
    task drive_key;
        input value;
        begin @(negedge clk); mode_n = value; end
    endtask
    task accepted_press;
        begin drive_key(0); wait(dut.stable_n === 0); #2; end
    endtask
    task accepted_release;
        begin drive_key(1); wait(dut.stable_n === 1); #2; end
    endtask
    task check_events;
        input integer expected_color, expected_freeze;
        begin
            if (color_events != expected_color || freeze_events != expected_freeze)
                $fatal(1, "events: color %0d/%0d freeze %0d/%0d", color_events,
                       expected_color, freeze_events, expected_freeze);
        end
    endtask

    initial begin
        ticks(4); @(negedge clk); rst_n=1; ticks(6);
        if (color_requested !== 0 || freeze_requested !== 0) $fatal(1, "reset defaults");

        // Sub-debounce press pulses cannot create either event.
        repeat(3) begin drive_key(0); ticks(2); drive_key(1); ticks(5); end
        ticks(8); check_events(0,0);

        // The short event waits for an accepted release, including release bounce.
        accepted_press(); ticks(2); check_events(0,0);
        drive_key(1); ticks(2); drive_key(0); ticks(5); check_events(0,0);
        accepted_release(); check_events(1,0);
        ticks(HOLD*3); check_events(1,0);

        // End just before the long event: the accepted release wins at that edge.
        accepted_press(); ticks(HOLD-DEBOUNCE-2);
        accepted_release(); check_events(2,0);

        // One additional held clock reaches the long-press boundary exactly once.
        accepted_press(); ticks(HOLD-1); check_events(2,0);
        ticks(1); check_events(2,1);
        if (freeze_requested !== 1) $fatal(1, "long hold did not freeze");
        ticks(HOLD*4); check_events(2,1);
        accepted_release(); ticks(8); check_events(2,1);

        // A second long press resumes and does not change the display mode.
        accepted_press(); ticks(HOLD); check_events(2,2);
        if (freeze_requested !== 0) $fatal(1, "second long hold did not resume");
        drive_key(1); ticks(2); drive_key(0); ticks(6); check_events(2,2);
        accepted_release(); ticks(8); check_events(2,2);

        // Short presses remain available after a consumed long press.
        accepted_press(); ticks(3); accepted_release(); check_events(3,2);
        if (color_requested !== 1) $fatal(1, "short release did not change color mode");

        // Reset while held clears both requests and restarts the long timer.
        accepted_press(); ticks(7);
        @(negedge clk); rst_n=0; ticks(3);
        if (color_requested !== 0 || freeze_requested !== 0) $fatal(1, "reset while held");
        @(negedge clk); rst_n=1;
        wait(dut.stable_n === 0); #2;
        ticks(HOLD-1); check_events(3,2);
        ticks(1); check_events(3,3);
        accepted_release(); ticks(8); check_events(3,3);
        if (color_requested !== 0 || freeze_requested !== 1) $fatal(1, "post-reset hold behavior");

        $display("PASS: synchronized debounce, press/release bounce, short release, exact long boundary, single event per hold, no short after long, resume and reset while held.");
        $finish;
    end
    initial begin #100000; $fatal(1, "timeout"); end
endmodule
