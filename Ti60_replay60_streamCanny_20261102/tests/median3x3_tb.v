`timescale 1ns/1ps
// median3x3 测试:
//   1. 脉冲响应延迟固定 4 拍
//   2. 前 2 行 / 前 2 列透传原始像素(不填 0)
//   3. 内部像素等于 3x3 真值中值 -- 黄金模型用计数法, 不复用 DUT 的排序网络
module median3x3_tb;
    localparam W = 12;
    localparam H = 6;

    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, de=0, hs=0, vs=0;
    reg [11:0] xin=0, yin=0;
    reg [7:0]  gin=0;

    wire de0,hs0,vs0; wire [11:0] x0,y0; wire [7:0] g0;

    median3x3 #(.WIDTH(W)) dut(
        .clk(clk),.rst_n(rst_n),.de_in(de),.hs_in(hs),.vs_in(vs),
        .x_in(xin),.y_in(yin),.gray_in(gin),
        .de_out(de0),.hs_out(hs0),.vs_out(vs0),.x_out(x0),.y_out(y0),.gray_out(g0)
    );

    // 测试图案: 与坐标一一对应, 便于反推期望值
    function [7:0] pix;
        input [11:0] px, py;
        begin
            pix = px[7:0]*8 + py[7:0]*3;
        end
    endfunction

    // 3x3 真值中值: 统计法, 与 DUT 的排序网络无关
    function automatic [7:0] true_median;
        input [11:0] cx, cy;
        integer i, j, less, equal;
        reg [71:0] w;
        reg [7:0] cand, other;
        begin
            for (i=0;i<3;i=i+1)
                for (j=0;j<3;j=j+1)
                    w[(i*3+j)*8 +: 8] = pix(cx-2+j, cy-2+i);
            true_median = 8'hxx;
            for (i=0;i<9;i=i+1) begin
                cand  = w[i*8 +: 8];
                less  = 0;
                equal = 0;
                for (j=0;j<9;j=j+1) begin
                    other = w[j*8 +: 8];
                    if (other < cand)      less  = less + 1;
                    else if (other == cand) equal = equal + 1;
                end
                if (less <= 4 && (less + equal) > 4) true_median = cand;
            end
        end
    endfunction

    task ticks; input integer n; integer i;
        begin for(i=0;i<n;i=i+1) begin @(posedge clk); #1; end end
    endtask

    task frame;
        integer x, y;
        begin
            @(negedge clk); vs=1; de=0; xin=0; yin=0; gin=0; ticks(3);
            @(negedge clk); vs=0; ticks(3);
            for (y=0;y<H;y=y+1) begin
                for (x=0;x<W;x=x+1) begin
                    @(negedge clk); de=1; xin=x; yin=y; gin=pix(x,y);
                end
                @(negedge clk); de=0; ticks(4);
            end
            ticks(10);
        end
    endtask

    integer errs=0, checked=0, border_checked=0, interior_checked=0;
    reg checking = 0;                  // 延迟测量期间关掉比对, 避免误报
    always @(posedge clk) begin
        #1;
        if (rst_n && checking && de0) begin
            checked = checked + 1;
            if (x0 < 2 || y0 < 2) begin
                border_checked = border_checked + 1;
                if (g0 !== pix(x0,y0)) begin
                    errs = errs + 1;
                    if (errs <= 5)
                        $display("BORDER MISMATCH (x=%0d,y=%0d) got=%0d exp=%0d",
                                 x0, y0, g0, pix(x0,y0));
                end
            end else begin
                interior_checked = interior_checked + 1;
                if (g0 !== true_median(x0,y0)) begin
                    errs = errs + 1;
                    if (errs <= 5)
                        $display("MEDIAN MISMATCH (x=%0d,y=%0d) got=%0d exp=%0d",
                                 x0, y0, g0, true_median(x0,y0));
                end
            end
        end
    end

    integer lat, i;
    initial begin
        ticks(6); @(negedge clk); rst_n=1; ticks(8);

        // ---- 延迟测量: 单周期脉冲从输入到输出应为 4 拍 ----
        @(negedge clk); de=1; xin=0; yin=0; gin=8'hA5;
        lat=0;
        for (i=0;i<10;i=i+1) begin
            @(posedge clk); #1;
            if (de0 && g0 === 8'hA5 && lat == 0) lat = i + 1;
        end
        if (lat !== 4) begin errs=errs+1; $display("LATENCY FAIL: %0d expect 4", lat); end
        @(negedge clk); de=0; gin=0; xin=0; yin=0; ticks(12);

        // ---- 两帧光栅 ----
        @(negedge clk); checking=1;
        frame;
        frame;
        @(negedge clk); de=0; ticks(20); checking=0;

        if (checked < 100)
            $fatal(1,"not enough output samples: %0d", checked);
        if (border_checked == 0 || interior_checked == 0)
            $fatal(1,"border/interior not exercised: %0d/%0d", border_checked, interior_checked);
        if (errs !== 0)
            $fatal(1,"median3x3 mismatches: %0d", errs);
        $display("PASS: median3x3 4-stage latency (%0d), %0d samples (%0d border passthrough, %0d true 3x3 median).",
                 lat, checked, border_checked, interior_checked);
        $finish;
    end
    initial begin #2000000; $fatal(1,"timeout"); end
endmodule
