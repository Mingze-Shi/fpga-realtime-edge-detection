// ============================================================================
// median3x3.v -- 3x3 中值滤波去噪 (高阶挑战第 1 项)
//
// 功能: 在灰度化之后、Sobel 边缘检测之前插入 3x3 中值滤波,
//       对 9 个像素值排序取中位数输出, 抑制椒盐噪声, 提升边缘检测质量。
//       插入位置: sc431_sobel_video.v 中 gray_registered -> u_sobel 之间。
//
// 排序网络 (并行比较网络, 无串行排序, 共 19 个 8bit 比较器):
//   第 1 级: 窗口 3 行各自做 3 元素升序排序   -- 3 个 sort3 并行
//   第 2 级: 列间归并, 取 max(lo) / med(md) / min(hi)
//   第 3 级: med3(max_lo, med_md, min_hi)     -- 即 9 像素中值
//   该网络是 3x3 中值的经典实现, 输出与 9 元素全排序取第 5 个完全一致。
//
// 结构:
//   - 行缓冲: even/odd 乒乓双行 RAM, 保存 y-1 / y-2 两行,
//             与 sobel_stream.v 相同的写法, 由综合器推断成块 RAM。
//   - 流水线: 固定 4 拍 (S1 行缓冲读 / S2 窗口移位+行内排序 /
//             S3 列间归并 / S4 输出), 满足 148.5MHz 视频时钟。
//   - 边界: 前 2 行 / 前 2 列窗口不完整, 透传原始像素, 不留黑边。
//   - 坐标: x / y / de / hs / vs 与像素同延迟原样透传,
//           下游 sobel_stream 复用 x 作为行缓冲读写地址。
// ============================================================================
module median3x3 #(
    parameter integer WIDTH = 1920
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de_in,
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [7:0]  gray_in,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out,
    output reg  [11:0] x_out,
    output reg  [11:0] y_out,
    output reg  [7:0]  gray_out
);

    // ---------- 3 元素升序排序: 返回 {lo, mid, hi} ----------
    function [23:0] sort3;
        input [7:0] a, b, c;
        reg   [7:0] lo, hi;
        begin
            lo = (a < b) ? a : b;
            hi = (a < b) ? b : a;
            if      (c < lo) sort3 = {c,  lo, hi};
            else if (c < hi) sort3 = {lo, c,  hi};
            else             sort3 = {lo, hi, c };
        end
    endfunction

    // ---------- 3 元素取中值: max(min(a,b), min(max(a,b),c)) ----------
    function [7:0] med3;
        input [7:0] a, b, c;
        reg   [7:0] lo, hi, m;
        begin
            lo = (a < b) ? a : b;
            hi = (a < b) ? b : a;
            m  = (hi < c) ? hi : c;
            med3 = (lo > m) ? lo : m;
        end
    endfunction

    // ---------- 行缓冲: 保存 y-1 与 y-2 两行 ----------
    reg [7:0] line_even [0:WIDTH-1];
    reg [7:0] line_odd  [0:WIDTH-1];
    reg [7:0] q_even, q_odd;

    // ---------- S1: 输入打拍 + 行缓冲读 ----------
    reg [7:0]  p_s1;
    reg [11:0] x_s1, y_s1;
    reg        de_s1, hs_s1, vs_s1;

    // ---------- S2: 窗口移位 + 行内排序 ----------
    reg [7:0]  d0_0, d0_1;                      // 第 y   行: x-1 / x-2
    reg [7:0]  d1_0, d1_1;                      // 第 y-1 行
    reg [7:0]  d2_0, d2_1;                      // 第 y-2 行
    reg [7:0]  lo0, md0, hi0;
    reg [7:0]  lo1, md1, hi1;
    reg [7:0]  lo2, md2, hi2;
    reg [7:0]  p_s2;
    reg [11:0] x_s2, y_s2;
    reg        de_s2, hs_s2, vs_s2, valid_s2;

    // ---------- S3: 列间归并 ----------
    reg [7:0]  maxlo, medmd, minhi;
    reg [7:0]  p_s3;
    reg [11:0] x_s3, y_s3;
    reg        de_s3, hs_s3, vs_s3, valid_s3;

    wire [7:0] up1 = y_s1[0] ? q_even : q_odd;   // (x, y-1)
    wire [7:0] up2 = y_s1[0] ? q_odd  : q_even;  // (x, y-2)

    // 窗口: 列为 x-2 / x-1 / x, 行为 y-2 / y-1 / y
    wire [23:0] s_row0 = sort3(d0_1, d0_0, p_s1);
    wire [23:0] s_row1 = sort3(d1_1, d1_0, up1);
    wire [23:0] s_row2 = sort3(d2_1, d2_0, up2);

    // S1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q_even<=0; q_odd<=0;
            p_s1<=0; x_s1<=0; y_s1<=0;
            de_s1<=0; hs_s1<=1; vs_s1<=1;
        end else begin
            if (de_in) begin
                q_even <= line_even[x_in];
                q_odd  <= line_odd[x_in];
                if (y_in[0]) line_odd[x_in]  <= gray_in;
                else         line_even[x_in] <= gray_in;
            end
            p_s1  <= gray_in;
            x_s1  <= x_in;
            y_s1  <= y_in;
            de_s1 <= de_in;
            hs_s1 <= hs_in;
            vs_s1 <= vs_in;
        end
    end

    // S2: 窗口移位寄存 + 3 行并行排序
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d0_0<=0; d0_1<=0; d1_0<=0; d1_1<=0; d2_0<=0; d2_1<=0;
            lo0<=0; md0<=0; hi0<=0;
            lo1<=0; md1<=0; hi1<=0;
            lo2<=0; md2<=0; hi2<=0;
            p_s2<=0; x_s2<=0; y_s2<=0;
            de_s2<=0; hs_s2<=1; vs_s2<=1; valid_s2<=0;
        end else begin
            if (de_s1) begin
                d0_0 <= p_s1;  d0_1 <= d0_0;
                d1_0 <= up1;   d1_1 <= d1_0;
                d2_0 <= up2;   d2_1 <= d2_0;
            end
            {lo0, md0, hi0} <= s_row0;
            {lo1, md1, hi1} <= s_row1;
            {lo2, md2, hi2} <= s_row2;
            p_s2     <= p_s1;
            x_s2     <= x_s1;
            y_s2     <= y_s1;
            de_s2    <= de_s1;
            hs_s2    <= hs_s1;
            vs_s2    <= vs_s1;
            valid_s2 <= de_s1 && (x_s1 >= 12'd2) && (y_s1 >= 12'd2);
        end
    end

    // S3: 列间归并 -- max(行最小) / med(行中值) / min(行最大)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            maxlo<=0; medmd<=0; minhi<=0;
            p_s3<=0; x_s3<=0; y_s3<=0;
            de_s3<=0; hs_s3<=1; vs_s3<=1; valid_s3<=0;
        end else begin
            maxlo <= (lo0 > lo1) ? ((lo0 > lo2) ? lo0 : lo2)
                                 : ((lo1 > lo2) ? lo1 : lo2);
            medmd <= med3(md0, md1, md2);
            minhi <= (hi0 < hi1) ? ((hi0 < hi2) ? hi0 : hi2)
                                 : ((hi1 < hi2) ? hi1 : hi2);
            p_s3     <= p_s2;
            x_s3     <= x_s2;
            y_s3     <= y_s2;
            de_s3    <= de_s2;
            hs_s3    <= hs_s2;
            vs_s3    <= vs_s2;
            valid_s3 <= valid_s2;
        end
    end

    // S4: 输出 -- 9 像素中值 = med3(maxlo, medmd, minhi)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_out<=0; hs_out<=1; vs_out<=1;
            x_out<=0; y_out<=0; gray_out<=0;
        end else begin
            de_out   <= de_s3;
            hs_out   <= hs_s3;
            vs_out   <= vs_s3;
            x_out    <= x_s3;
            y_out    <= y_s3;
            gray_out <= valid_s3 ? med3(maxlo, medmd, minhi) : p_s3;
        end
    end

endmodule
