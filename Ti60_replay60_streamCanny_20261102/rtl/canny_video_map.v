// Decimated traditional Canny, complete frame connectivity, double-buffered map.
// Input and display ports share the pixel clock. HDMI timing never stalls.
module canny_video_map #(
    parameter WIDTH=1920,HEIGHT=1080,SCALE_LOG2=2,
    parameter PROCESS_WIDTH=WIDTH>>SCALE_LOG2,PROCESS_HEIGHT=HEIGHT>>SCALE_LOG2,
    parameter CONTROL_ENABLE=0
)(
    input clk,rst_n,
    input de_in,vs_in,
    input [11:0] x_in,y_in,
    input [7:0] gray_in,
    input [10:0] high_threshold,
    input work_reset,
    input display_vs,
    input [11:0] display_x,display_y,
    output edge_out,valid_out,busy
);
    localparam CW=PROCESS_WIDTH, CH=PROCESS_HEIGHT;
    function integer gcd;
        input integer a,b;
        integer temporary;
        begin
            while(b!=0) begin temporary=a%b;a=b;b=temporary;end
            gcd=a;
        end
    endfunction
    localparam GX=gcd(WIDTH,CW),GY=gcd(HEIGHT,CH);
    localparam XNUM=CW/GX,XDEN=WIDTH/GX,YNUM=CH/GY,YDEN=HEIGHT/GY;
    localparam AW=$clog2(CW*CH);
    // synthesis translate_off
    initial begin
        if(CW<7 || CH<7 || CW>WIDTH || CH>HEIGHT)
            $fatal(1,"Canny processing dimensions must be at least 7x7 and no larger than input");
    end
    // synthesis translate_on
    // Rational nearest-neighbor sampling of the complete source image. A point
    // is selected at the first source coordinate mapping to each output cell.
    // 1920x1080 -> 640x480: x every 3, y residues 0/3/5/7 modulo 9.
    wire [23:0] input_x_product=x_in*XNUM,input_y_product=y_in*YNUM;
    wire [11:0] sample_x=input_x_product/XDEN,sample_y=input_y_product/YDEN;
    wire sample_de=de_in && input_x_product%XDEN<XNUM
        && input_y_product%YDEN<YNUM && x_in<WIDTH && y_in<HEIGHT;
    reg sampled_de,sampled_vs;
    reg [11:0] sampled_x,sampled_y;
    reg [7:0] sampled_gray;
    wire fd,fv;wire [11:0] fx,fy;wire [1:0] fc;
    reg fv_previous,display_vs_previous;
    reg [2:0] display_coordinate_valid;
    wire map_edge;
    wire [23:0] display_x_product=display_x*XNUM,display_y_product=display_y*YNUM;
    wire [11:0] map_x=display_x_product/XDEN,map_y=display_y_product/YDEN;
    reg [11:0] map_x_registered,map_y_registered;
    reg [AW-1:0] display_addr;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            fv_previous<=0;display_vs_previous<=0;display_coordinate_valid<=0;
            sampled_de<=0;sampled_vs<=0;sampled_x<=0;sampled_y<=0;sampled_gray<=0;
            map_x_registered<=0;map_y_registered<=0;display_addr<=0;
        end
        else begin
            fv_previous<=fv;display_vs_previous<=display_vs;
            sampled_de<=sample_de;sampled_vs<=vs_in;
            sampled_x<=sample_x;sampled_y<=sample_y;sampled_gray<=gray_in;
            // Split division, row-address multiplication and RAM lookup into
            // three clocks. The caller compensates the display latency.
            map_x_registered<=map_x;map_y_registered<=map_y;
            display_addr<=map_y_registered*CW+map_x_registered;
            display_coordinate_valid<={display_coordinate_valid[1:0],display_x<WIDTH && display_y<HEIGHT};
        end
    end
    assign edge_out=display_coordinate_valid[2] && map_edge;
    canny_frontend #(.WIDTH(CW)) frontend(
        .clk(clk),.rst_n(rst_n),.de_in(sampled_de),.vs_in(sampled_vs),
        .x_in(sampled_x),.y_in(sampled_y),.gray_in(sampled_gray),
        .high_threshold(high_threshold),.de_out(fd),.vs_out(fv),
        .x_out(fx),.y_out(fy),.class_out(fc));
    canny_hysteresis #(.WIDTH(CW),.HEIGHT(CH),.CONTROL_ENABLE(CONTROL_ENABLE)) hysteresis(
        .clk(clk),.rst_n(rst_n),.frame_start(fv && !fv_previous),
        .de_in(fd),.x_in(fx),.y_in(fy),.class_in(fc),
        .display_frame_start(display_vs && !display_vs_previous),
        .work_reset(work_reset),
        .display_addr(display_addr),.edge_out(map_edge),.display_valid(valid_out),.busy(busy));
endmodule
