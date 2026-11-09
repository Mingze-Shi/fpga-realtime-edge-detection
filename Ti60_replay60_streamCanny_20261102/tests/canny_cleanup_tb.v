`timescale 1ns/1ps
// Directed contour shapes, independent of the neighbour-count implementation.
module canny_cleanup_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg [17:0] classes;
    canny_stream #(.WIDTH(32),.HEIGHT(24)) dut(
        .clk(clk),.rst_n(1'b0),.de_in(1'b0),.vs_in(1'b0),
        .x_in(12'd0),.y_in(12'd0),.gray_in(8'd0),.high_threshold(11'd64));
    task check;
        input [17:0] shape;
        input expected;
        begin
            classes=shape;
            force dut.p00=classes[1:0]; force dut.p01=classes[3:2];
            force dut.p02=classes[5:4]; force dut.p10=classes[7:6];
            force dut.p11=classes[9:8]; force dut.p12=classes[11:10];
            force dut.p20=classes[13:12]; force dut.p21=classes[15:14];
            force dut.p22=classes[17:16];
            #1;
            if(dut.keep!==expected) $fatal(1,"cleanup shape %h expected %b",shape,expected);
        end
    endtask
    initial begin
        // Each row is left-to-right; the centre is the decision under test.
        check({6'b000000,6'b001000,6'b000000},0); // isolated strong
        check({6'b000000,6'b001010,6'b000000},0); // two-pixel speck / endpoint
        check({6'b000000,6'b101010,6'b000000},1); // horizontal contour
        check({6'b001000,6'b001000,6'b001000},1); // vertical contour
        check({6'b100000,6'b001000,6'b000010},1); // diagonal contour
        check({6'b000010,6'b001000,6'b100000},1); // other diagonal
        check({6'b001000,6'b001010,6'b000000},1); // corner
        check({6'b001000,6'b101010,6'b000000},1); // T junction
        check({6'b000000,6'b010101,6'b000000},0); // weak-only contour
        check({6'b000000,6'b100101,6'b000000},1); // supported weak continuation
        check({6'b000000,6'b100010,6'b000000},0); // no centre: do not fill gaps
        $display("PASS: isolated specks/endpoints rejected; straight, diagonal, corner and junction contours retained; weak connectivity checked");
        $finish;
    end
endmodule
