`timescale 1ns/1ps
module frame_write_commit_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,aw=0,b=0,finish=0;
    reg [31:0] addr=0;
    wire done,fault;wire [31:0] committed;
    integer count=0;
    frame_write_commit dut(.clk(clk),.rst_n(rst),.aw_accept(aw),.b_accept(b),
        .frame_data_end(finish),.frame_addr(addr),.committed(done),.committed_addr(committed),.fault(fault));
    always @(posedge clk) begin #1;if(done) begin
        if(committed!==32'h1000+count*32'h1000) $fatal(1,"AXI completion address order");
        count=count+1;
    end end
    task ticks;input integer n;integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk);#2;end end
    endtask
    task issue;input integer a;input integer bursts;integer i;
        begin
            for(i=0;i<bursts;i=i+1) begin @(negedge clk);aw=1;ticks(1);@(negedge clk);aw=0;end
            @(negedge clk);addr=a;finish=1;ticks(1);@(negedge clk);finish=0;
        end
    endtask
    task response;input integer n;integer i;
        begin for(i=0;i<n;i=i+1) begin @(negedge clk);b=1;ticks(1);@(negedge clk);b=0;ticks(2);end end
    endtask
    initial begin
        ticks(3);@(negedge clk);rst=1;
        issue('h1000,3);issue('h2000,2);ticks(5);
        if(count || fault) $fatal(1,"descriptor falsely marked complete before B response");
        response(2);if(count) $fatal(1,"partial frame response marked complete");
        response(1);if(count!=1) $fatal(1,"first frame not committed");
        response(2);if(count!=2) $fatal(1,"second frame completion lost across next frame");
        issue('h3000,1);issue('h4000,1);issue('h5000,1);issue('h6000,1);
        response(4);if(count!=6 || fault) $fatal(1,"four-entry completion queue");
        issue('h7000,1);issue('h8000,1);issue('h9000,1);issue('ha000,1);issue('hb000,1);
        if(!fault) $fatal(1,"metadata queue overflow not detected");
        @(negedge clk);rst=0;ticks(2);
        if(fault || done) $fatal(1,"completion queue reset");
        $display("PASS: AXI B-response frame commit, delayed responses across subsequent frames, four metadata entries, order, overflow and reset; no image RAM");
        $finish;
    end
    initial begin #1000000;$fatal(1,"commit timeout");end
endmodule
