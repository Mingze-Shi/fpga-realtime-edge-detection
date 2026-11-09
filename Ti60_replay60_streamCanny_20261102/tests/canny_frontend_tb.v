`timescale 1ns/1ps
module canny_frontend_tb;
    localparam W=24,H=18,F=8;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,vs=0;reg [11:0] x=0,y=0;
    reg [7:0] gray=0;reg [10:0] threshold=32;
    wire od,ov;wire [11:0] ox,oy;wire [1:0] oc;
    reg [7:0] pixels[0:W*H*F-1];reg [1:0] expected[0:W*H*F-1];
    reg [10:0] thresholds[0:F-1];
    canny_frontend #(.WIDTH(W)) dut(.clk(clk),.rst_n(rst),.de_in(de),.vs_in(vs),
        .x_in(x),.y_in(y),.gray_in(gray),.high_threshold(threshold),
        .de_out(od),.vs_out(ov),.x_out(ox),.y_out(oy),.class_out(oc));
    integer f,i,j,k,seen=0,frame=-1;reg prev_vs=0;
    reg [9:0] de_pipe=0,vs_pipe=0;reg [11:0] xp[0:9],yp[0:9];
    integer s,warmup=0;
    always @(posedge clk) begin
        if(!rst) begin de_pipe=0;vs_pipe=0;warmup=0;end
        else begin
            for(s=9;s>0;s=s-1) begin xp[s]=xp[s-1];yp[s]=yp[s-1];end
            xp[0]=x;yp[0]=y;de_pipe={de_pipe[8:0],de};vs_pipe={vs_pipe[8:0],vs};
            warmup=warmup+1;
            #1;
            if(warmup>=10 && {od,ov}!=={de_pipe[9],vs_pipe[9]}) $fatal(1,"frontend sync latency");
            if(ov && !prev_vs) frame=frame+1;
            prev_vs=ov;
            if(od) begin
                if(ox!==xp[9] || oy!==yp[9]) $fatal(1,"frontend coordinate latency");
                if(oc!==expected[frame*W*H+oy*W+ox])
                    $fatal(1,"frontend frame=%0d x=%0d y=%0d got=%0d expected=%0d",frame,ox,oy,oc,expected[frame*W*H+oy*W+ox]);
                seen=seen+1;
            end
        end
    end
    task ticks;input integer n;integer t;
        begin for(t=0;t<n;t=t+1) begin @(posedge clk);#2;end end
    endtask
    initial begin
        $readmemh("test_output/canny_pixels.hex",pixels);
        $readmemh("test_output/canny_classes.hex",expected);
        $readmemh("test_output/canny_thresholds.hex",thresholds);
        ticks(4);@(negedge clk);rst=1;
        for(f=0;f<F;f=f+1) begin
            @(negedge clk);threshold=thresholds[f];vs=1;ticks(4);
            @(negedge clk);vs=0;ticks(12);
            for(j=0;j<H;j=j+1) begin
                for(i=0;i<W;i=i+1) begin
                    @(negedge clk);de=1;x=i;y=j;gray=pixels[f*W*H+j*W+i];
                    ticks(1);
                    // Gapped pixels exercise decimation without treating gaps as rows.
                    if((i+j+f)%3==0) begin @(negedge clk);de=0;ticks(3);end
                end
                @(negedge clk);de=0;ticks(5);
            end
            ticks(20);
        end
        if(seen!=W*H*F) $fatal(1,"frontend lost pixels %0d",seen);
        $display("PASS: Gaussian, squared Sobel, all NMS directions, thresholds, borders, frame reset, sparse DE and ten-cycle sync; %0d pixels",seen);
        $finish;
    end
    initial begin #1000000;$fatal(1,"frontend timeout");end
endmodule
