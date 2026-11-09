// ============================================================================
// canny_stream_tb.v -- pin down the streaming Canny's pipeline latency and its
// causal (window) displacement.
//
// Two synthetic frames are pushed through:
//   * a vertical step at x = W/2   -> the edge_pixel column tells us the horizontal
//     displacement between x_out and the pixel the decision actually describes
//   * a horizontal step at y = H/2 -> same for the vertical axis
//
// It also prints the de_in -> de_out latency, which is the number the colour /
// grey delay chains in sc431_sobel_video.v have to match.
// ============================================================================
`timescale 1ns/1ps
module canny_stream_tb;
    localparam W = 64, H = 24;
    localparam VSTEP = 32, HSTEP = 12;

    reg clk = 0, rst_n = 0;
    reg de = 0;
    reg [11:0] x = 0, y = 0;
    reg [7:0] g = 0;
    reg [10:0] thr = 11'd64;

    wire edge_pixel, dout, vout;
    wire [11:0] xo, yo;

    canny_stream #(.WIDTH(W), .HEIGHT(H)) dut(
        .clk(clk), .rst_n(rst_n),
        .de_in(de), .vs_in(1'b0), .x_in(x), .y_in(y), .gray_in(g),
        .high_threshold(thr),
        .edge_out(edge_pixel), .de_out(dout), .vs_out(vout), .x_out(xo), .y_out(yo)
    );

    always #5 clk = ~clk;

    integer t = 0;
    integer first_de_in = -1, first_de_out = -1;
    integer edge_count = 0;
    integer vertical_edges = 0, horizontal_edges = 0;
    integer min_vx = 9999, max_vx = -1;
    integer min_hy = 9999, max_hy = -1;

    // Frame selector: 0 = vertical step, 1 = horizontal step.
    integer frame = 0;

    always @(posedge clk) begin
        t = t + 1;
        if(de  && first_de_in  < 0) first_de_in  = t;
        if(dout && first_de_out < 0) first_de_out = t;
        if(dout && edge_pixel) begin
            edge_count = edge_count + 1;
            if(frame == 0) begin
                vertical_edges = vertical_edges + 1;
                if(xo < min_vx) min_vx = xo;
                if($signed({1'b0,xo}) > max_vx) max_vx = xo;
                if(vertical_edges <= 8)
                    $display("  vertical   edge_pixel: x_out=%0d y_out=%0d", xo, yo);
            end else begin
                horizontal_edges = horizontal_edges + 1;
                if(yo < min_hy) min_hy = yo;
                if($signed({1'b0,yo}) > max_hy) max_hy = yo;
                if(horizontal_edges <= 8)
                    $display("  horizontal edge_pixel: x_out=%0d y_out=%0d", xo, yo);
            end
        end
    end

    task feed_frame;
        begin
            for(integer r = 0; r < H; r = r + 1) begin
                for(integer i = 0; i < W; i = i + 1) begin
                    @(negedge clk);
                    de = 1; x = i[11:0]; y = r[11:0];
                    g = (frame == 0) ? ((i < VSTEP) ? 8'd0 : 8'd255)
                                     : ((r < HSTEP) ? 8'd0 : 8'd255);
                end
                // horizontal gap so the line buffers can be observed
                @(negedge clk); de = 0; repeat(4) @(negedge clk);
            end
            repeat(32) @(negedge clk);
        end
    endtask

    initial begin
        repeat(4) @(negedge clk); rst_n = 1; repeat(4) @(negedge clk);

        frame = 0; feed_frame;
        frame = 1; feed_frame;

        $display("latency de_in -> de_out : %0d clocks", first_de_out - first_de_in);
        $display("vertical step at x=%0d : %0d edge_pixel pixels, x_out range %0d..%0d",
                 VSTEP, vertical_edges, min_vx, max_vx);
        $display("horizontal step at y=%0d: %0d edge_pixel pixels, y_out range %0d..%0d",
                 HSTEP, horizontal_edges, min_hy, max_hy);

        if(first_de_out-first_de_in != 14) $fatal(1,"expected 14-clock Canny latency");
        if(edge_count == 0) $fatal(1, "no edges produced");
        if(vertical_edges == 0 || horizontal_edges == 0)
            $fatal(1, "one orientation produced no edges");
        if(vertical_edges > 3*H || horizontal_edges > 3*W)
            $fatal(1, "edges are thicker than 3 pixels");
        $display("PASS: streaming Canny produced thin edges in both orientations");
        $finish;
    end

    initial begin #2000000; $fatal(1, "timeout"); end
endmodule
