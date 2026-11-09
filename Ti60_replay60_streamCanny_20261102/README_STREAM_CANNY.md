# 流式 Canny：二值化清晰度与丢帧修复（2026-11-02）

后续 5×5 去噪修改见 `FILTER5X5.md`。当前流式路径使用精确 5×5 中值和 5×5 高斯；下文的 3×3、13 拍及原交付文件数据仅描述此前版本。

基线：`Ti60_replay60_20261101`（六十帧回放版，2026-11-01 21:09）。

## 一、问题与根因

两个现象来自同一处设计：

```
1080p 输入 → 抽取到 640×480 → 整帧写三张位图 → 多趟滞后扫描 → 下一帧换缓冲显示 → 最近邻放大 3×
```

**清晰度**：`CANNY_WIDTH/HEIGHT = 640×480`。1920/640 = 3（每 3 列取 1 列），1080/480 = 2.25（每 9 行取 4 行）。显示端用 `map_y*CW+map_x` 查表，每个位图像素变成 3 列 × 2~3 行的方块，垂直方向 2/3 行交替。

**为什么不能直接改成 1920×1080**：`canny_hysteresis` 为整帧存三张位图（候选 + 双缓冲确认），640×480 就占 114/256 个 Memory Block；像素数 ×6.75 后需要约 770 块。差一个数量级。

**丢帧/慢半拍**：滞后是串行状态机，背景/强边 2 拍、弱边 18 拍，多趟收敛。一趟约 6~12 ms，从帧尾才开始，必然跨过下一个 VS；结果只在下一个 VS 换缓冲，且扫描期间 `capture_write` 关闭 → 整帧被跳过。实测效果：二值图每 2 帧更新一次（30 fps），内容比画面晚 2 帧（33 ms），边缘密时掉到 20 fps。

## 二、改法

删掉：抽取映射、三张整帧位图、多趟滞后状态机、按 VS 换缓冲。

换成：`Gaussian 3×3 → Sobel → NMS → 双阈值 → 3×3 局部滞后`，全部在像素流水线里，1 像素/拍，1920×1080 原生。

延迟账（@148.5 MHz，一拍一个像素）：

| 段 | 拍数 |
|---|---|
| median3x3（原有） | 4 |
| canny_frontend（Gaussian + Sobel + NMS + 双阈值） | 10 |
| 滞后邻域窗口 | 2 |
| 输出寄存 | 1 |
| **合计** | **13** |

因果 3×3 窗口让输出标注的像素比实际像素靠前 4 列/行（3 个窗口 + 滞后窗口各 1）。因此彩色/灰度各多延 4 级，与边缘对齐：

- `color_pipe[21]`、`gray_delay[20]`（原为 8 / 7）
- `de/hs/vs` 一起后移 13 拍（`output_phase`），保证数据与同步仍是一条完整视频流

语义保持：SW1/SW2 阈值、模式 0 左右分屏、模式 2 冻结快照与红边、模式 2 对比态**不叠红边**（新增 `!compare_request`，与 `README_DELAY_COMPARE.md` 描述一致）、模式 3 六十帧回放、CNN 取景框与识别全部沿用。

## 三、资源与时序（本次构建实测）

| | 改前 | 改后 |
|---|---|---|
| Memory Block | 249 / 256（97.3%） | **145 / 256（56.6%）** |
| DSP Block | 58 / 160 | 58 / 160 |
| 二值化分辨率 | 640×480 → 3× 放大 | **1920×1080 原生** |
| 二值图额外延迟 | 2 帧（33 ms） | **13 拍（约 0.09 µs）** |
| 二值图更新率 | 30 fps，忙时 20 | **60 fps** |
| 最小建立裕量 | +0.415 ns | **+0.385 ns** |
| 负 slack 条数 | 0 | **0** |

流式 Canny 子树实测 20 块（front 18 + 滞后 2）。整帧位图那 114 块被释放，换来 111 块余量。

## 四、烧录文件

| 文件 | 字节 | SHA-256 |
|---|---|---|
| `delivery_stream_canny/ti60f225_oob.bit` | 2,832,534 | `10D5930A3CE4905CE0F1D0CD7BA891D10737AB0278FC1E5140EFF7716E85827A` |
| `delivery_stream_canny/ti60f225_oob.hex` | 2,832,594 | `79211EE32B9FC5C112CDEA74DE49114284EF0C7E8CB10037B33D40214646068C` |

临时验证用 JTAG + bit；写 Flash 必须走 JTAG-SPI 桥方式。

## 五、验证范围

**已通过**：Efinity map / interface / pnr / pgm 四步全 PASS；时序报告 0 条负 slack；资源在器件内。

**未做**：
- 本机 iverilog 被 Device Guard 拦截（`ivl.exe was blocked`），新模块未跑逻辑仿真。13 拍延迟与 4 像素因果位移是按电路逐级推导，不是实测。已附 `tests/canny_stream_tb.v`，在能跑 iverilog 的终端执行即可得到确切拍数与边落位：

  ```powershell
  tools\iverilog-portable\Library\bin\iverilog.exe -g2012 -s canny_stream_tb -o test_output\canny_stream.vvp rtl\canny_stream.v rtl\canny_frontend.v rtl\canny_window3x3.v tests\canny_stream_tb.v
  tools\iverilog-portable\Library\bin\vvp.exe test_output\canny_stream.vvp
  ```

- 未上板。

**回归套件未改坏**：新通路是独立参数 `CANNY_STREAM_ENABLE`，默认 0。`canny_video_tb` / `canny_overlay_tb` / `canny_resolution_tb` 会探入 `u_canny.hysteresis.state` 等旧层级，它们实例化时不传该参数，仍走 legacy 分支，行为与改动前一致。只有顶层 `ti60f225_oob_top` 显式打开。

`tests/check_canny_build.py` 的 `processing_resolution` 与 `tests/check_cnn_build.py` 的 `edge_processing_resolution` 已同步改为 `[1920,1080]`。

## 六、上板检查项

1. **模式 0 右半**：边应为 1 像素细，斜边无 3 像素台阶，横边粗细不再一跳一跳。
2. **挥手对比**：右半二值边应与左半灰度同步，不再有明显滞后。
3. **模式 2/3 红边**：应贴合物体轮廓。若整体偏 1~2 像素，说明 4 像素因果补偿估偏，把 `RGB_TAP` / `GRAY_TAP` / `PHASE_TAP` 三者同时 ±N（必须同改，否则数据与同步脱开）。
4. **模式 1**：彩色 + 取景框 + 字幕位置是否仍居中（整条流水线多了 13 拍，取景框几何用 `x_output`，理论上有约 13 像素横向偏移，肉眼不可见）。
5. **模式 3**：60 帧回放、自动播放、手动切帧应完全不变。

## 七、回退

| 想要 | 改法 |
|---|---|
| 回到原 640×480 整帧 Canny | `.CANNY_STREAM_ENABLE(0)` |
| 回到纯 Sobel 全分辨率 | `.CANNY_ENABLE(0)` |
| 当前（流式 Canny） | `.CANNY_ENABLE(1), .CANNY_STREAM_ENABLE(1)` |

## 八、已知限制

1. **滞后是局部的**：弱边只要 3×3 邻域内有强边就保留，不做全图连通泛洪。斜边可能有 1~2 像素断点。要更连续可换 5×5 窗口（约 +10 块，余量充足）或加一次 1 像素膨胀。
2. **边界 6 像素被屏蔽**：沿用 `canny_frontend` 的 `nvalid = nx>=6 && ny>=6`。
3. **基础延迟仍在**：DDR 帧缓存约 1 帧，两个半边一样。这次只去掉了 Canny 额外的 2 帧。
4. **DDR 存储为 RGB565**：灰度由 8 bit 反算，有色阶损失，与本次两个问题无关。
5. **模式 2 对比态仍是已知缺陷**：`frame_buffer_V4/ddr_rd_buffer.v` 是 10/31 23:23 那版（15 拍交替突发），本次未改动。长按 SW3 进入对比态仍可能出现横向噪声带。

## 九、改动文件

| 文件 | 改动 |
|---|---|
| `rtl/canny_stream.v` | **新增**：1920×1080 流式 Canny，13 拍 |
| `rtl/sc431_sobel_video.v` | 新增 `CANNY_STREAM_ENABLE`；三路 generate（stream / legacy / sobel）；彩色与灰度延迟链扩到 21/20；de/hs/vs 后移 13 拍；对比态屏蔽红边 |
| `rtl/ti60f225_oob_top.v` | 打开 `CANNY_STREAM_ENABLE(1)` |
| `ti60f225_oob.xml` | 加入 `rtl/canny_stream.v` |
| `tests/canny_stream_tb.v` | **新增**：延迟与因果位移探针（未运行） |
| `tests/check_canny_build.py` | `processing_resolution` 改 `[1920,1080]`，滞后描述同步 |
| `tests/check_cnn_build.py` | `edge_processing_resolution` 改 `[1920,1080]` |

`rtl/canny_video_map.v`、`rtl/canny_hysteresis.v` 保留不动，只服务 legacy 分支与旧用例。
