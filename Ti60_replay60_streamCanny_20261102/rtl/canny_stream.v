// ============================================================================
// canny_stream.v -- full-resolution streaming Canny, one pixel per clock.
//
// Replaces the old "decimate to 640x480 -> store three whole-frame bit planes
// -> multi-pass hysteresis scan -> publish at a later vsync" pipeline. There is
// no frame map and no scan any more: Gaussian 5x5 -> Sobel -> NMS -> dual
// threshold -> local 3x3 hysteresis, all in the pixel pipeline.
//
// Latency is 14 clocks from gray_in to edge_out, so the binary map lands on the
// SAME frame as the colour/grey picture instead of two frames later, and every
// frame produces a result independently of how many edges the scene contains.
//
// Quality note: the hysteresis is local (a weak pixel survives when one of its
// eight neighbours is strong) rather than a full-frame connectivity flood.
// That keeps edges thin and connected, at 1/100 of the storage. The exact flood
// implementation is kept in canny_hysteresis.v for reference but is no longer
// in the data path.
// ============================================================================
module canny_stream #(
    parameter integer WIDTH  = 1920,
    parameter integer HEIGHT = 1080
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de_in,
    input  wire        vs_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [7:0]  gray_in,
    input  wire [10:0] high_threshold,
    output reg         edge_out,
    output reg         de_out,
    output reg         vs_out,
    output reg  [11:0] x_out,
    output reg  [11:0] y_out
);

    // ---- Traditional Canny front end: Gaussian -> Sobel -> NMS -> 2 thresholds.
    //      class_out: 0 = background, 1 = weak, 2 = strong.  11 clocks. ----
    wire        fd, fv;
    wire [11:0] fx, fy;
    wire [1:0]  fc;
    canny_frontend #(.WIDTH(WIDTH),.GAUSSIAN5(1)) u_front(
        .clk(clk), .rst_n(rst_n),
        .de_in(de_in), .vs_in(vs_in), .x_in(x_in), .y_in(y_in), .gray_in(gray_in),
        .high_threshold(high_threshold),
        .de_out(fd), .vs_out(fv), .x_out(fx), .y_out(fy), .class_out(fc)
    );

    // ---- 3x3 neighbourhood of the thresholded classes.  2 clocks. ----
    wire        hd, hv;
    wire [11:0] hx, hy;
    wire [1:0]  p00, p01, p02, p10, p11, p12, p20, p21, p22;
    canny_window3x3 #(.WIDTH(WIDTH), .BITS(2)) u_hyst(
        .clk(clk), .rst_n(rst_n),
        .de_in(fd), .vs_in(fv), .x_in(fx), .y_in(fy), .data_in(fc),
        .de_out(hd), .vs_out(hv), .x_out(hx), .y_out(hy),
        .p00(p00), .p01(p01), .p02(p02),
        .p10(p10), .p11(p11), .p12(p12),
        .p20(p20), .p21(p21), .p22(p22)
    );

    // Require support on both sides of a thin contour (at least two of eight
    // non-background neighbours). Reject isolated strong noise as well as weak
    // noise; strong classification alone previously bypassed all cleanup.
    wire any_strong = (p00 == 2'b10) || (p01 == 2'b10) || (p02 == 2'b10) ||
                      (p10 == 2'b10) ||                     (p12 == 2'b10) ||
                      (p20 == 2'b10) || (p21 == 2'b10) || (p22 == 2'b10);
    wire [3:0] neighbour_count = {3'b0,(p00!=0)} + {3'b0,(p01!=0)}
        + {3'b0,(p02!=0)} + {3'b0,(p10!=0)} + {3'b0,(p12!=0)}
        + {3'b0,(p20!=0)} + {3'b0,(p21!=0)} + {3'b0,(p22!=0)};
    wire keep = neighbour_count>=2 &&
        ((p11 == 2'b10) || (p11 == 2'b01 && any_strong));

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            de_out <= 0; vs_out <= 0; x_out <= 0; y_out <= 0; edge_out <= 0;
        end else begin
            de_out   <= hd;
            vs_out   <= hv;
            x_out    <= hx;
            y_out    <= hy;
            // The line RAM is intentionally not reset. Mask the incomplete
            // class neighbourhood at each frame/line start to reject old data.
            edge_out <= hd && hx>=10 && hy>=10 && hx<WIDTH && hy<HEIGHT && keep;
        end
    end
endmodule
