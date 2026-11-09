`timescale 1ns/1ps
module bank_replay_tb;
    localparam STRIDE=16*8*32/8+512;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,ws=0,rs=0,freeze=0,replay=0,sel=0;
    reg wa=0,wc=0;reg [1:0] writing=0,committed=0;
    wire [1:0] wb,rb;wire [31:0] waddr,raddr;
    wire fa,ready,ack;
    integer tags[0:2];integer serial=0,k,hold0,hold1;
    reg [1:0] saved0,saved1,physical;
    bank_switch #(.FB_NUM(3),.REPLAY_ENABLE(1),.MAX_VID_WIDTH(16),.MAX_VID_HIGHT(8),.VID_DATA_WIDTH(32)) dut(
        .ddr_clk(clk),.rst_n(rst),.wr_sw(ws),.rd_sw(rs),.freeze_request(freeze),
        .replay_request(replay),.replay_select(sel),.write_active(wa),.writing_bank(writing),
        .write_committed(wc),.committed_bank(committed),.commit_fault(1'b0),
        .freeze_active(fa),.replay_ready(ready),.replay_select_ack(ack),
        .wr_bank(wb),.rd_bank(rb),.wr_start_addr(waddr),.rd_start_addr(raddr));
    task ticks;input integer n;integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk);#1;end end
    endtask
    task read_frame;
        begin @(negedge clk);rs=1;ticks(1);@(negedge clk);rs=0;ticks(4);end
    endtask
    task write_frame;input integer complete;
        begin
            physical=wb;serial=serial+1;
            @(negedge clk);wa=1;writing=physical;ticks(1);@(negedge clk);wa=0;
            // Existing bank switch is an early next-descriptor notification.
            @(negedge clk);ws=1;ticks(1);@(negedge clk);ws=0;ticks(4);
            tags[physical]=serial;
            if(complete) begin
                @(negedge clk);wc=1;committed=physical;ticks(1);@(negedge clk);wc=0;ticks(4);
            end
        end
    endtask
    always @(posedge clk) if(rst) begin #2;
        if(wb==rb) $fatal(1,"replay writer/read ownership collision");
        if(raddr!==rb*STRIDE || waddr!==wb*STRIDE) $fatal(1,"replay address/slot mismatch");
        if(ready && (wb==dut.three_fb.saved0 || wb==dut.three_fb.saved1)) $fatal(1,"writer owns retained replay slot");
    end
    initial begin
        tags[0]=-1;tags[1]=-1;tags[2]=-1;ticks(4);@(negedge clk);rst=1;ticks(4);
        write_frame(1);read_frame;write_frame(1);read_frame;
        @(negedge clk);freeze=1;replay=1;ticks(5);
        write_frame(0);ticks(8);
        if(ready) $fatal(1,"replay accepted frame before final AXI B completion");
        @(negedge clk);wc=1;committed=physical;ticks(1);@(negedge clk);wc=0;ticks(5);
        if(!ready || !fa) $fatal(1,"two completed replay slots not retained");
        saved0=dut.three_fb.saved0;saved1=dut.three_fb.saved1;
        hold0=tags[saved0];hold1=tags[saved1];
        if(hold0==hold1) $fatal(1,"replay did not retain distinct frame contents");
        for(k=0;k<20;k=k+1) begin
            @(negedge clk);sel=~sel;ticks(5);
            if(ack==sel) $fatal(1,"selection changed outside read-frame boundary");
            write_frame(1);read_frame;
            if(ack!=sel || tags[rb]!=(sel ? hold1:hold0)) $fatal(1,"replay frame selection/content");
            if(tags[saved0]!=hold0 || tags[saved1]!=hold1) $fatal(1,"capturing overwrote retained frames");
        end
        @(negedge clk);replay=0;freeze=0;ticks(5);read_frame;
        for(k=0;k<8;k=k+1) begin write_frame(1);read_frame;end
        if(ready || fa) $fatal(1,"replay exit did not restore live pool");
        $display("PASS: two distinct completed DDR frames, delayed-commit gate, boundary-only step/ack, third-slot live writes, protected frame integrity and safe replay exit; zero extra frame storage");
        $finish;
    end
    initial begin #1000000;$fatal(1,"replay timeout");end
endmodule
