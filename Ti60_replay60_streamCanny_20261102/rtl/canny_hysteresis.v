// Exact 8-connected hysteresis. Repeated in-place raster passes terminate only
// at a fixed point. No limit on weak-chain length. Capture pauses while busy.
// Only complete results are published, at display_frame_start.
module canny_hysteresis #(parameter WIDTH=480, HEIGHT=270,CONTROL_ENABLE=0)(
    input clk,rst_n,
    input frame_start,de_in,
    input [11:0] x_in,y_in,
    input [1:0] class_in,
    input display_frame_start,
    input work_reset,
    input [$clog2(WIDTH*HEIGHT)-1:0] display_addr,
    output edge_out,
    output reg display_valid,
    output busy
);
    localparam N=WIDTH*HEIGHT;
    localparam AW=$clog2(N);
    localparam WAIT_FRAME=0,CAPTURE=1,PIX_READ=2,PIX_TEST=3,
        NEIGH_READ=4,NEIGH_TEST=5,COPY_READ=6,COPY_WRITE=7,WAIT_SWAP=8;
    reg [3:0] state;
    // Three bits per pixel: immutable candidate mask + two confirmed maps.
    // The background confirmed map is both the work plane and next display.
    reg candidates[0:N-1];
    reg edge_a[0:N-1],edge_b[0:N-1];
    reg candidate_q,qa,qb,display_bank;
    wire [1:0] class_q={display_bank ? qa:qb,candidate_q};
    reg [AW-1:0] scan_addr;
    reg [11:0] scan_x,scan_y;
    reg [11:0] capture_next_x,capture_next_y;
    reg [2:0] neighbor;
    reg changed;
    integer neighbor_x,neighbor_y;
    reg neighbor_valid;
    reg [AW-1:0] read_addr;
    // The front end's three causal windows displace the sample by (3,3).
    // Modular remapping writes each address exactly once, including zero borders.
    wire [11:0] capture_x=x_in>=3 ? x_in-12'd3:x_in+WIDTH-3;
    wire [11:0] capture_y=y_in>=3 ? y_in-12'd3:y_in+HEIGHT-3;
    wire [AW-1:0] capture_addr=capture_y*WIDTH+capture_x;
    wire capture_write=state==CAPTURE && de_in && x_in<WIDTH && y_in<HEIGHT && !(CONTROL_ENABLE && work_reset);
    wire promote_write=state==NEIGH_TEST && neighbor_valid && class_q[1];
    wire class_write=rst_n && !(CONTROL_ENABLE && work_reset) && (capture_write || promote_write);
    wire [AW-1:0] class_write_addr=capture_write ? capture_addr:scan_addr;
    wire confirmed_write_data=capture_write ? class_in==2:1'b1;
    wire [AW-1:0] read_a_addr=display_bank ? read_addr:display_addr;
    wire [AW-1:0] read_b_addr=display_bank ? display_addr:read_addr;
    always @* begin
        neighbor_x=scan_x;neighbor_y=scan_y;
        case(neighbor)
            0: begin neighbor_x=scan_x-1;neighbor_y=scan_y-1;end
            1: neighbor_y=scan_y-1;
            2: begin neighbor_x=scan_x+1;neighbor_y=scan_y-1;end
            3: neighbor_x=scan_x-1;
            4: neighbor_x=scan_x+1;
            5: begin neighbor_x=scan_x-1;neighbor_y=scan_y+1;end
            6: neighbor_y=scan_y+1;
            7: begin neighbor_x=scan_x+1;neighbor_y=scan_y+1;end
        endcase
        neighbor_valid=neighbor_x>=0 && neighbor_x<WIDTH && neighbor_y>=0 && neighbor_y<HEIGHT;
        read_addr=scan_addr;
        if(state==NEIGH_READ || state==NEIGH_TEST)
            read_addr=neighbor_valid ? neighbor_y*WIDTH+neighbor_x:0;
    end
    // Synchronous read and single write port, no reset on inferred block RAM.
    always @(posedge clk) begin
        if(state==PIX_READ || state==NEIGH_READ) candidate_q<=candidates[read_addr];
        if(rst_n && capture_write) candidates[capture_addr]<=class_in!=0;
        if(class_write && display_bank) edge_a[class_write_addr]<=confirmed_write_data;
        if(class_write && !display_bank) edge_b[class_write_addr]<=confirmed_write_data;
        if(read_a_addr<N) qa<=edge_a[read_a_addr];
        if(read_b_addr<N) qb<=edge_b[read_b_addr];
    end
    assign edge_out=display_valid ? (display_bank ? qb:qa):1'b0;
    assign busy=state!=WAIT_FRAME;
    task advance_pixel;
        input promoted;
        begin
            if(scan_addr==N-1) begin
                scan_addr<=0;scan_x<=0;scan_y<=0;changed<=0;
                if(changed || promoted) state<=PIX_READ;
                else state<=WAIT_SWAP;
            end else begin
                scan_addr<=scan_addr+1'b1;
                if(scan_x==WIDTH-1) begin scan_x<=0;scan_y<=scan_y+1'b1;end
                else scan_x<=scan_x+1'b1;
                if(promoted) changed<=1;
                state<=PIX_READ;
            end
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_FRAME;scan_addr<=0;scan_x<=0;scan_y<=0;
            neighbor<=0;changed<=0;display_bank<=0;display_valid<=0;
            capture_next_x<=0;capture_next_y<=0;
        end else if(CONTROL_ENABLE && work_reset) begin
            state<=WAIT_FRAME;display_valid<=0;scan_addr<=0;scan_x<=0;scan_y<=0;
            capture_next_x<=0;capture_next_y<=0;neighbor<=0;changed<=0;
        end else case(state)
            WAIT_FRAME: if(frame_start) begin
                state<=CAPTURE;capture_next_x<=0;capture_next_y<=0;
            end
            CAPTURE: begin
                // A new VS before the last pixel aborts a malformed/incomplete frame.
                if(frame_start) begin capture_next_x<=0;capture_next_y<=0;end
                else if(de_in) begin
                    if(x_in!=capture_next_x || y_in!=capture_next_y) state<=WAIT_FRAME;
                    else if(x_in==WIDTH-1 && y_in==HEIGHT-1) begin
                        scan_addr<=0;scan_x<=0;scan_y<=0;changed<=0;state<=PIX_READ;
                    end else if(x_in==WIDTH-1) begin
                        capture_next_x<=0;capture_next_y<=capture_next_y+1'b1;
                    end else capture_next_x<=capture_next_x+1'b1;
                end
            end
            PIX_READ: state<=PIX_TEST;
            PIX_TEST: if(class_q==1) begin neighbor<=0;state<=NEIGH_READ;end
                      else advance_pixel(0);
            NEIGH_READ: state<=NEIGH_TEST;
            NEIGH_TEST: if(neighbor_valid && class_q[1]) advance_pixel(1);
                else if(neighbor==7) advance_pixel(0);
                else begin neighbor<=neighbor+1'b1;state<=NEIGH_READ;end
            WAIT_SWAP: if(display_frame_start) begin
                display_bank<=~display_bank;display_valid<=1;state<=WAIT_FRAME;
            end
            default: state<=WAIT_FRAME;
        endcase
    end
endmodule
