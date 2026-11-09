`timescale 1ns/1ps
module canny_hysteresis_tb;
    localparam W=16,H=12,N=W*H,F=7,AW=$clog2(N);
    reg clk=0;always #5 clk=~clk;
    reg rst=0,fs=0,de=0,dfs=0;
    reg [11:0] x=0,y=0;reg [1:0] cls=0;reg [AW-1:0] addr=0;
    wire edge_pixel,valid,busy;
    reg [1:0] source[0:N*F-1];reg expected[0:N*F-1];
    canny_hysteresis #(.WIDTH(W),.HEIGHT(H)) dut(
        .clk(clk),.rst_n(rst),.frame_start(fs),.de_in(de),.x_in(x),.y_in(y),.class_in(cls),
        .display_frame_start(dfs),.display_addr(addr),.edge_out(edge_pixel),.display_valid(valid),.busy(busy));
    task ticks;input integer n;integer t;
        begin for(t=0;t<n;t=t+1) begin @(posedge clk);#1;end end
    endtask
    integer f,i,j,xx,yy,count,previous_bank;
    initial begin
        $readmemh("test_output/hysteresis_source.hex",source);
        $readmemh("test_output/hysteresis_expected.hex",expected);
        ticks(4);@(negedge clk);rst=1;ticks(3);
        if(valid!==0 || edge_pixel!==0) $fatal(1,"uninitialized map visible");
        // A dropped capture sample must never publish stale RAM contents.
        @(negedge clk);fs=1;ticks(1);@(negedge clk);fs=0;de=1;x=0;y=0;cls=2;
        ticks(1);@(negedge clk);x=2;ticks(1);@(negedge clk);de=0;
        if(dut.state!=0 || valid) $fatal(1,"incomplete capture accepted");
        for(f=0;f<F;f=f+1) begin
            @(negedge clk);fs=1;ticks(1);@(negedge clk);fs=0;
            for(j=0;j<H;j=j+1) begin
                for(i=0;i<W;i=i+1) begin
                    xx=i>=3 ? i-3:i+W-3;yy=j>=3 ? j-3:j+H-3;
                    @(negedge clk);de=1;x=i;y=j;cls=source[f*N+yy*W+xx];
                end
                @(negedge clk);de=0;ticks(2);
            end
            previous_bank=dut.display_bank;count=0;
            while(dut.state!=8) begin
                // New source frames during computation must not overwrite work RAM.
                @(negedge clk);fs=(count%113==0);de=1;cls=2;x=0;y=0;
                ticks(1);count=count+1;
                if(count>100000) $fatal(1,"hysteresis failed to converge");
                if(dut.display_bank!=previous_bank) $fatal(1,"map changed before display VS");
            end
            @(negedge clk);fs=0;de=0;ticks(10);
            if(dut.display_bank!=previous_bank) $fatal(1,"premature publish");
            @(negedge clk);dfs=1;ticks(1);@(negedge clk);dfs=0;ticks(1);
            if(!valid || busy) $fatal(1,"completed map not published");
            for(i=0;i<N;i=i+1) begin
                @(negedge clk);addr=i;ticks(1);
                if(edge_pixel!==expected[f*N+i]) $fatal(1,"hysteresis frame=%0d addr=%0d got=%0d expected=%0d",f,i,edge_pixel,expected[f*N+i]);
            end
        end
        @(negedge clk);rst=0;ticks(2);
        if(valid!==0 || edge_pixel!==0) $fatal(1,"reset leaked old edges");
        $display("PASS: exact flood-fill reference, long reverse chains, isolated weak components, diagonals, frame skipping, incomplete capture rejection, atomic map swap, reset");
        $finish;
    end
    initial begin #20000000;$fatal(1,"hysteresis timeout");end
endmodule
