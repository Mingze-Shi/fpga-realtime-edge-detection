`timescale 1ns/1ps
module taffy_photo_tb;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,en=1,de=0,vs=0;
    reg [11:0] x=0,y=0;
    reg [7:0] gray=0,photo[0:4095];
    wire matched,valid;
    wire [21:0] error;
    taffy_photo_match #(.ROI_X(16),.ROI_Y(8),.SAMPLE_STEP(2)) dut(
        .clk(clk),.rst_n(rst),.enable(en),.de(de),.vs(vs),.x(x),.y(y),.gray(gray),
        .matched(matched),.result_valid(valid),.last_error(error));
    task ticks;input integer n;integer k;
        begin repeat(n) begin @(posedge clk);#2;end end
    endtask
    task boundary;
        begin @(negedge clk);de=0;vs=1;ticks(4);@(negedge clk);vs=0;ticks(4);end
    endtask
    task image;input integer kind;integer i,v,j;
        begin
            for(i=0;i<4096;i=i+1) begin
                @(negedge clk);de=1;x=17+2*(i%64);y=9+2*(i/64);
                j=kind==3 ? (i/64)*64+63-i%64:i;
                v=photo[j];
                if(kind==1) v=v+10;
                if(kind==2) v=128;
                if(kind==4) v=v*4/5;
                if(kind==5) v=((i*73+i/64*47)%256);
                if(kind==8) v=96+v*3/10;
                if(kind==9) v=(i%64<32) ? 0:255;
                if(kind==10) v=(i/64<32 && i%64<40) ? photo[i]:255;
                if(kind==11) v=i%64>=8 ? photo[i-8]:255;
                if(v>255) v=255;
                gray=v;
                // Omit a sample and corrupt another coordinate in bad frames.
                if(kind==6 && i==100) de=0;
                if(kind==7 && i==100) x=x+2;
                ticks(1);
                @(negedge clk);de=0;ticks(1);
            end
            ticks(4);boundary;ticks(15000);
        end
    endtask
    initial begin
        $readmemh("assets/taffy/gray.hex",photo);
        ticks(4);@(negedge clk);rst=1;boundary;
        image(0);if(!valid || matched || error>4) $fatal(1,"first exact frame %d",error);
        image(0);if(matched) $fatal(1,"requires three frames");
        image(0);if(!matched || error>4) $fatal(1,"exact image rejected");
        image(1);if(!matched) $fatal(1,"brightness offset rejected");
        image(4);if(!matched) $fatal(1,"modest contrast change rejected");
        repeat(3) image(8);
        if(!matched) $fatal(1,"relaxed tolerance must accept 30-percent contrast");
        repeat(3) image(9);
        if(matched) $fatal(1,"straight boundary accepted");
        image(2);if(matched || !valid) $fatal(1,"blank accepted");
        repeat(3) image(10);if(!matched) $fatal(1,"partial contour rejected");
        repeat(3) image(11);if(!matched) $fatal(1,"translated contour rejected");
        repeat(3) image(3);if(!matched) $fatal(1,"approximate mirrored local contour rejected");
        repeat(3) image(5);if(matched) $fatal(1,"unrelated texture accepted");
        image(6);if(matched || valid) $fatal(1,"incomplete frame accepted");
        image(7);if(matched || valid) $fatal(1,"wrong sample order accepted");
        repeat(3) image(0);
        if(!matched) $fatal(1,"failed to reacquire");
        @(negedge clk);en=0;ticks(4);
        if(matched || valid) $fatal(1,"disabled result stale");
        @(negedge clk);en=1;
        image(0);if(matched) $fatal(1,"streak not reset");
        @(negedge clk);rst=0;ticks(3);
        if(matched || valid) $fatal(1,"reset stale");
        $display("PASS: partial-contour exact/brightness/contrast, partial crop, translation and approximate mirror, three-frame confirmation, blank/straight-line/texture rejection, malformed frames, disable and reset.");
        $finish;
    end
    initial begin #100000000;$fatal(1,"timeout");end
endmodule
