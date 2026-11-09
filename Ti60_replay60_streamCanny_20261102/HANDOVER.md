# 交接说明 · Ti60 流式 Canny 版（2026-11-02）

## 一、这是什么

Efinix **Ti60F225** 开发板上的摄像头边缘检测 + 表情识别工程，基于 `Ti60_replay60_20261101`（六十帧回放版）修改。

本版把原来 **640×480 整帧位图 Canny** 换成了 **1920×1080 流式 Canny**，解决两个问题：

1. **二值化画面不是 1080p**——原来内部降采样到 640×480，再按 3×3 最近邻放大，斜边有 3 像素台阶。现在是原生 1920×1080，单像素边。
2. **二值化页比实时画面慢**——原来要收完整帧、存三张位图、多趟扫描、下一帧才显示，实测慢 2 帧（33 ms）、更新率只有 30 fps。现在是流水线，延迟 13 拍（约 0.09 µs），恒定 60 fps。

副作用是资源不升反降：Memory Block 249 → 145，逻辑 42,130 → 37,775 XLR。

## 二、目录结构

```
├── HANDOVER.md                  ← 本文件，先读这个
├── README_STREAM_CANNY.md       改动推导、上板检查项、回退方法
├── BOARD_RESOURCES.md           资源/时序账目、板级现状、风险清单
├── rtl/                         全部 RTL
│   ├── canny_stream.v           ★ 新增：1920×1080 流式 Canny
│   ├── sc431_sobel_video.v      ★ 改：三路 generate + 延迟链 + 相位
│   ├── ti60f225_oob_top.v       ★ 改：打开 CANNY_STREAM_ENABLE(1)
│   ├── canny_video_map.v        保留：旧整帧 Canny（legacy 分支用）
│   ├── canny_hysteresis.v       保留：旧全图滞后（legacy 分支用）
│   └── ...                      其余未改动
├── tests/                       回归用例
│   ├── canny_stream_tb.v        ★ 新增：延迟/因果位移探针（未运行，见下）
│   └── ...                      其余未改动
├── assets/ cnn/ ip/             字模、CNN 权重、IP
├── tools/iverilog-portable/     内置 iverilog（Windows），跑回归用
├── test_output/                 回归固件与历史日志
├── delivery_stream_canny/       ★ 烧录文件 + 时序/布局/层级报告
├── baseline_backup/             改动前三个文件的原件
├── ti60f225_oob.xml/.sdc/.peri.xml   Efinity 工程文件
├── build_burnable.ps1           只出可烧录文件（约 5 分钟）
└── build_cnn.ps1                完整回归 + 构建（较慢）
```

## 三、环境要求

| 项目 | 要求 |
|---|---|
| Efinity | 2026.1（器件库 Titanium Ti60F225，时序模型 I3） |
| 系统 | Windows |
| 构建脚本默认路径 | `D:\efinity\2026.1`，不同机器用 `-EfinityBin` 指定 |
| 跑回归 | 内置 `tools/iverilog-portable`，无需另装 |

## 四、构建与烧录

```powershell
# 1) 只出可烧录文件（推荐，约 5 分钟）
powershell -ExecutionPolicy Bypass -File .\build_burnable.ps1 -EfinityBin "D:\efinity\2026.1\bin"

# 2) 完整回归 + 构建（会跑 20 组仿真，耗时较长）
powershell -ExecutionPolicy Bypass -File .\build_cnn.ps1
```

产物在 `outflow_cnn\ti60f225_oob.bit` / `.hex`。

**烧录**：
- 临时验证：JTAG 直接下载 `.bit`（掉电失效）
- 写 Flash：JTAG-SPI 桥方式写 `.hex`（断电保留）

本包 `delivery_stream_canny\` 里已经有一份编译好的 bit/hex，可直接烧：

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `ti60f225_oob.bit` | 2,832,534 | `10D5930A3CE4905CE0F1D0CD7BA891D10737AB0278FC1E5140EFF7716E85827A` |
| `ti60f225_oob.hex` | 2,832,594 | `79211EE32B9FC5C112CDEA74DE49114284EF0C7E8CB10037B33D40214646068C` |

## 五、运行状态与资源

| 项目 | 基线 | 本版 |
|---|---|---|
| Memory Block | 249 / 256（97.3%） | **145 / 256（56.6%）** |
| DSP Block | 58 / 160 | 58 / 160 |
| XLR（逻辑） | 42,130 / 60,800 | 37,775 / 60,800 |
| 二值化分辨率 | 640×480 → 3× 放大 | **1920×1080 原生** |
| 二值图额外延迟 | 2 帧（33 ms） | **13 拍（约 0.09 µs）** |
| 二值图更新率 | 30 fps（忙时 20） | **60 fps** |
| 最小建立裕量 | +0.415 ns | +0.385 ns |
| 最小保持裕量 | +0.026 ns | +0.026 ns |
| 负 slack | 0 | 0 |

细节见 `BOARD_RESOURCES.md`。

## 六、按键与模式（未变）

| 模式 | 画面 | SW1 / SW2 | SW3 |
|---|---|---|---|
| 0 | 左灰度 / 右二值边缘 | 调 Canny 阈值 | 切模式 1 |
| 1 | 彩色 + 取景框 + 表情字幕 | **调数字曝光 1/1~1/8** | 切模式 2 |
| 2 | 冻结快照 | 无 | 切模式 3；长按切对比态 |
| 3 | 最近 60 帧回放 | 更早 / 更新一帧 | 切模式 0 |

SW0 复位。按键低电平有效。

## 七、已知问题（交接重点）

1. **`tests/canny_stream_tb.v` 从未运行过。** 开发机的 Device Guard 拦了 `ivl.exe`。它用来测 13 拍延迟和 4 像素因果位移，在能跑 iverilog 的机器上执行即可：
   ```powershell
   tools\iverilog-portable\Library\bin\iverilog.exe -g2012 -s canny_stream_tb -o test_output\canny_stream.vvp rtl\canny_stream.v rtl\canny_frontend.v rtl\canny_window3x3.v tests\canny_stream_tb.v
   tools\iverilog-portable\Library\bin\vvp.exe test_output\canny_stream.vvp
   ```
   如果实测不是 13 拍，改 `sc431_sobel_video.v` 里的 `PHASE_TAP`（并同步 `RGB_TAP`/`GRAY_TAP`），三者必须一起改。

2. **红边对齐是推导值，未上板逐像素核对。** 若模式 2/3 的红边整体偏 1~2 像素，同样调上述三个常量。

3. **模式 2 对比态仍是已知缺陷。** `frame_buffer_V4/ddr_rd_buffer.v` 是 2026-10-31 23:23 版（15 拍交替突发），长按 SW3 进对比态可能出现横向噪声带。本次未修。

4. **hold 余量仅 +0.026 ns**（基线同样）。换 Efinity 版本、换温度或换布局种子都可能翻负，长期维护建议单独加固一次。

5. **强光下画面发灰。** SC431 的曝光寄存器 `0x3e01/0x3e02` 写死在 I2C 初始化表，运行时不可调。可用模式 1 的 SW1 压到 1/8，或在模式 0 提高阈值，都是权宜。

6. **模式 1 的 SW1/SW2 是曝光，模式 0 是阈值**，现场容易按错。

## 八、回退

| 目标 | 操作 |
|---|---|
| 回到 640×480 整帧 Canny | `rtl/ti60f225_oob_top.v`：`.CANNY_STREAM_ENABLE(0)` |
| 回到纯 Sobel 全分辨率 | `.CANNY_ENABLE(0)` |
| 回到完全原始版本 | 用 `baseline_backup/` 里三个文件覆盖对应位置 |

legacy 分支保留完整，`canny_video_tb` / `canny_overlay_tb` / `canny_resolution_tb` 等旧用例仍走 legacy 路径，不受本次改动影响。
