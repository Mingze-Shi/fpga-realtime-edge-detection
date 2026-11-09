`timescale 1ns/1ps
module threshold_keys_tb;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, up_n=1, down_n=1;
    wire [10:0] value;
    threshold_keys #(.DEBOUNCE_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.increase_n(up_n),.decrease_n(down_n),
        .threshold_requested(value)
    );
    task ticks; input integer n; integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk); #1; end end
    endtask
    task check; input integer expected;
        begin if(value!==expected) $fatal(1,"threshold=%0d expected=%0d",value,expected); end
    endtask
    task press_up;
        begin @(negedge clk);up_n=0;ticks(12);@(negedge clk);up_n=1;ticks(12);end
    endtask
    task press_down;
        begin @(negedge clk);down_n=0;ticks(12);@(negedge clk);down_n=1;ticks(12);end
    endtask
    integer k;
    initial begin
        ticks(6);@(negedge clk);rst_n=1;ticks(8);check(32);
        // Pulses shorter than debounce must not become a press.
        repeat(3) begin @(negedge clk);up_n=0;ticks(2);@(negedge clk);up_n=1;ticks(3);end
        ticks(10);check(32);
        @(negedge clk);up_n=0;ticks(12);check(40);ticks(50);check(40);
        @(negedge clk);up_n=1;ticks(12);press_down;check(32);
        @(negedge clk);up_n=0;down_n=0;ticks(12);check(32);
        @(negedge clk);up_n=1;down_n=1;ticks(12);
        for(k=0;k<300;k=k+1) press_up;check(2032);
        for(k=0;k<300;k=k+1) press_down;check(16);
        @(negedge clk);rst_n=0;ticks(4);check(32);
        $display("PASS: button synchronization, bounce rejection, one event per hold, simultaneous cancellation, step direction, saturating limits and reset.");
        $finish;
    end
    initial begin #1000000;$fatal(1,"timeout");end
endmodule
