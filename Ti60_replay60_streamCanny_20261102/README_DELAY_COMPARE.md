# Ti60 左右延时对比版（2026-10-31）

2026-11-01 更新：模式 3 已增加冻结后自动慢放，操作与新构建目录见 [README_AUTOPLAY.md](README_AUTOPLAY.md)。下文为左右延时对比版本的原始记录。

本版在 `Ti60_CNN六帧缓存修复完整工程_20261031` 基础上，新增**模式 2 的左右延时对比**：左半屏显示 N 帧前的画面，右半屏显示实时画面，两格同屏、中间一条白色分隔线。左边不是定格，会跟着右边一起动，只是永远慢 N 帧。

六帧回放（模式 3）、冻结快照（模式 2 默认态）、Canny、CNN 五分类表情识别均未改动行为。

**本版已通过 Efinity 综合、接口生成、布局布线、编程文件生成，未上板验证。**

---

## 一、烧录文件

| 文件 | 大小 | 用途 |
| --- | --- | --- |
| `outflow_cnn/ti60f225_oob.bit` | 2,599,065 B | JTAG 临时下载，断电不保留 |
| `outflow_cnn/ti60f225_oob.hex` | 2,599,125 B | 经 JTAG-SPI 桥写入板上 Flash，断电保留 |

SHA-256：

```
DD5645A4C3EE6D6114704BD8B7A258079D684B28E2A13876097617EB23D9D37B  ti60f225_oob.bit
F15A6954786934D1722E1D5D13B29564B168BF648B73DEF687310FABF578B390  ti60f225_oob.hex
```

在 Efinity Programmer 中，临时测试用 JTAG 模式 + bit 文件；写 Flash 必须走 JTAG-SPI 桥方式，不能把 hex 当 bit 直接下载。工程沿用原桥镜像 `u10660A79.bit`：先加载桥，再擦写校验 Flash，最后加载应用 bit 使程序立即运行。

**建议先 JTAG 临时下载验证，确认画面正常后再写 Flash。** 本版涉及的 DDR 读时序改动只有板级实测能确认。

---

## 二、按键与画面

四个按键：SW0 复位，SW1/SW2 增减键，SW3 模式键。均为低电平有效。

| 模式 | 画面 | SW1 / SW2 短按 | SW3 短按 | SW3 长按（约 1 秒） |
| --- | --- | --- | --- | --- |
| **0** | 左半屏灰度原图 / 右半屏 Sobel 二值边缘 | Canny 阈值 ±8 | → 模式 1 | 冻结 / 恢复 |
| **1** | 彩色 + 红色边缘叠加 + 512×256 取景框 + 中文表情字幕 | Canny 阈值 ±8 | → 模式 2 | 冻结 / 恢复 |
| **2 默认态** | **冻结快照**：画面定格，并在同一帧上重算红色 Canny 边缘 | 无动作 | → 模式 3 | **切到对比态** |
| **2 对比态** | **左延时 N 帧 / 右实时**，中间 4 像素白色分隔线 | 时差 −1 / +1 | → 模式 3 | **切回快照态** |
| **3** | 最近六帧完整图像逐帧回放 | 更早一帧 / 更新一帧（0↔5 循环） | → 模式 0 | 重新锁定最近六帧 |

补充约定：

- 时差 N 取值 0~5，对应 0~83 ms（60 Hz 一帧 16.7 ms）。N=0 时左右完全重合，可用于当场验证两路对齐。
- 阈值范围 16~2032，步长 8，初始 32。
- 模式 3 的"更早/更新"是沿六帧历史前后翻，与模式 2 的时差不是同一个量：前者选"哪一帧"，后者选"落后几帧"。
- 离开模式 2 会清除对比态，下次进入仍是冻结快照，不记忆上次状态。
- 表情识别只在模式 1 运行。进入模式 1 后无需按键，识别持续自动进行；连续三帧同类才显示表情名，一次拒绝即清除。

---

## 三、实现原理

### 3.1 一行切成两半

显示行宽 1920 像素，AXI 数据宽度 512 bit，一拍 64 像素，所以**一行 = 30 拍**，**半行 = 15 拍**。

把读突发长度从 127（128 拍）改成 14（15 拍）后，突发序号 b 就有了固定含义：

- 左右：`b & 1`（0 = 左半屏，1 = 右半屏）
- 行号：`b >> 1`

读地址按

```
addr = (右半 ? 右槽基址 : 左槽基址) + 行号 × 1920 + 右半 × 960
```

逐突发生成。第 2k 个突发读左槽第 k 行前 960 字节，第 2k+1 个突发读右槽同一行后 960 字节，两段在显示端自然拼成一张左右分屏图，不需要额外的合成缓存。

### 3.2 左槽是一条延迟线

`replay6_slots` 内部维护最近六帧完整提交的槽位历史 `history[0..5]`（0 最新）。对比态下，每个读帧边界把读槽指向 `history[N]`，并且**不锁槽**（`locked` 保持 0），所以：

- 左边每帧都在更新，只是落后 N 帧，不是定格；
- 实时写入完全不受影响，历史照常滚动；
- 右半屏固定读 `history[0]`（最新提交帧），表现为"实时"。

`history[N]` 只在完整提交后入队，所以任一半屏都不会读到写了一半的帧。

### 3.3 冻结快照保持原样

模式 2 默认态仍是原来的冻结逻辑：冻结 DDR 读描述符（不是视频时钟），锁住当前槽位，写侧继续往别的槽轮流写；随后在冻结帧上重算 Canny 并叠加红边。

对比态通过 `compare_request` 屏蔽冻结请求（`freeze_request` 拉 0），并让 `frozen` 直接报"就绪"以便按键握手正常。两个状态互斥，靠长按 SW3 切换。

### 3.4 分隔线

`x_output` 落在 `WIDTH/2 ± 2` 时输出白色（4 像素宽），只在对比态生效，不进入识别取样。

### 3.5 不改动的部分

摄像头寄存器表、MIPI 接收、DDR3 控制器、ISP（去噪/debayer/白平衡/锐化/CCM/饱和度）、Canny 算法、阈值控制、六帧槽位管理、CNN 网络与权重、引脚约束与时钟约束均未改动。

---

## 四、资源与时序（本次构建实测）

Efinity 2026.1.132，器件 Ti60F225，Timing Model I3，顶层 `ti60f225_oob`。

| 项目 | 结果 |
| --- | --- |
| 触发器 FF | 11,770 |
| SRL | 1,196 |
| 加法器 | 4,032 |
| LUT | 18,454 |
| **片上 Memory Block** | **249 / 256**（剩余 7） |
| **DSP Block** | **65 / 160** |
| 时序（Slack） | 报告中列出的最差 8 条路径全部为正，最小 +0.084 ns |
| map / interface / pnr / pgm | 四项全部 PASS |

与上一版相比：Memory 仍为 249，未新增任何存储块；DSP 由 59 增至 65，增量来自读引擎里的 `行号 × 1920` 常量乘法被映射到 DSP（该式可改写为 `行号<<11 + 行号<<8` 以省回 DSP，本版未做）。

时序报告的 setup / hold 分项最差值请在 Efinity 的 Timing Analyzer 中按 `outflow_cnn/ti60f225_oob.timing.rpt` 核对；本表只给出路径级最小 Slack。

---

## 五、验证范围

### 已运行且通过

| 测试 | 覆盖内容 | 结果 |
| --- | --- | --- |
| `tests/split_read_tb.v` | 分屏读地址序列逐拍比对：左 `A+0`、右 `B+960`、下一行 `A+1920`、`B+2880`；非分屏模式为单个 30 拍突发、起始地址不变 | PASS |
| `tests/replay6_slots_tb.v` | 六帧槽位管理：321 次采集、294 次选择、提前冻结、延迟提交、读保护、故障注入 | PASS |
| `tests/expression_cnn_video_tb.v` | 模式 1 的 614,400 个输出像素逐点比对，取景框、中文表情字幕、九拍同步延迟 | PASS |
| Efinity map / interface / pnr / pgm | 综合、接口、布局布线、编程文件生成 | 全部 PASS |

### 未运行

- **完整回归**（`tests/run_all_tests.py`、`run_cnn_tests.py`、`run_expression_cnn_tests.py`、`run_replay6_tests.py --full`）在最后一次 RTL 修改之后**没有重跑**。`check_cnn_build.py` 的新鲜度检查因此会报 `regression_all_tests.log predates its RTL dependencies`，这是预期行为，不是 RTL 错误。上线前应在完整构建脚本 `build_cnn.ps1` 中跑一遍，它会自动执行全部回归并在失败时中止。
- **模式 2 两个子状态没有端到端用例**。现有 `expression_cnn_video_tb` 只跑模式 1，不覆盖冻结快照与对比态的切换。
- **板级实测**：本次未连接开发板，摄像头实拍、HDMI 实际输出、断电启动均未验证。

### 本轮构建的取舍

为尽快产出可烧录文件，本次直接执行 `map → interface → pnr → pgm`，跳过了构建脚本里的长回归（1080p 六帧全量仿真耗时数十分钟以上）。上述三项针对性测试是单独编译运行的。

---

## 六、已知限制与风险

1. **15 拍突发对 DDR 带宽的影响只能上板确认。** 每 960 字节就在两个槽之间跳，行命中率会下降。1080p60 读写各约 124 MB/s，理论余量充足，但实测若出现撕裂或周期性闪烁，说明读 FIFO 供不上，可改用整行 30 拍 + 上下分屏，或加深读 FIFO。
2. **时差上限 83 ms。** 历史固定六帧。要更长需把历史扩到 8 帧（约 160 ms），DDR 需多占 8 MB（10 个槽位改 12 个）。
3. **模式 2 的短按键有空按。** 为让 SW1/SW2 在对比态调时差，模式 2 整体屏蔽了阈值调节；因此在冻结快照态按 SW1/SW2 既不调阈值也无其他动作。
4. **模式 2 的长按 SW3 不再是"重新锁定"。** 它已改为"快照 ↔ 对比"切换。若需保留重新锁定，应把对比开关移到 SW1 长按（`threshold_keys` 需增加保持计时器）。
5. **分屏不缩放、不裁剪。** 左右各显示各自那一帧的一半视野，不是把整幅图压成一半。取景时应让目标落在对应半边。
6. **对比态不叠加红色边缘。** 该状态下冻结流程被屏蔽，Canny 工作面复位，画面为纯视频。

---

## 七、复现构建

```powershell
# 完整构建（含全部回归，失败即中止）
powershell -ExecutionPolicy Bypass -File .\build_cnn.ps1 -PythonExe "你的Python路径"

# 只出可烧录文件（跳过回归，约 6 分钟）
powershell -ExecutionPolicy Bypass -File .\build_burnable.ps1 -EfinityBin "D:\efinity\2026.1\bin"
```

默认 Efinity 路径 `D:\efinity\2026.1`，其他机器用 `-EfinityBin` 指定。

生成字模、检查分数显示等辅助脚本：

```powershell
python -X utf8 tools/make_cnn_expression_text.py   # 五类中文标签
python -X utf8 tools/make_score_text.py            # "得分 0.NN" 字模（本版未接线）
python -X utf8 tests/run_expression_cnn_tests.py   # 表情 CNN 回归
python -X utf8 tests/run_replay6_tests.py          # 六帧与 DDR 回归
```

---

## 八、文件清单

### 修改的既有文件

| 文件 | 改动 |
| --- | --- |
| `rtl/frame_buffer_V4/ddr_rd_buffer.v` | 新增 `split_enable` / `split_addr`；分屏时 `arlen` 固定 14、地址按行号与半行号生成；`read_stop` 改由拍计数驱动；非分屏路径算术不变 |
| `rtl/replay6_slots.v` | 新增 `delay_mode`、`live_slot`、`live_address`；对比态读槽跟随 `history[N]` 且不锁槽；延迟态 `frozen` 直接报就绪 |
| `rtl/frame_buffer_V4/ddr_buffer.v` | 透传 `split_request`、`live_address`，把 `split_request` 作为 `delay_mode` |
| `rtl/frame_buffer_V4/frame_buffer.v` | 透传 `split_request` |
| `rtl/sc431_sobel_video.v` | `compare_active` 子状态与 `compare_request` 输出；冻结请求屏蔽；4 像素分隔线；模式 2 屏蔽阈值调节 |
| `rtl/canny_snapshot_control.v` | 模式 2 也接受步进事件 |
| `rtl/ti60f225_oob_top.v` | 分屏请求接线 |

### 新增文件

| 文件 | 说明 |
| --- | --- |
| `tests/split_read_tb.v` | 分屏读地址序列测试 |
| `build_burnable.ps1` | 只跑 map/interface/pnr/pgm 的快速出包脚本 |
| `rtl/score_divider.v` | 得分百分比除法器（本版未接线） |
| `rtl/score_text.v` | "得分 0.NN" 字模（本版未接线，由 `tools/make_score_text.py` 生成） |
| `tools/make_score_text.py` | 上述字模生成器 |

### 得分显示（半成品，本版未启用）

`expression_cnn_decision_seq` 已新增 `score_denominator` 输出，`taffy_expression_cnn_core` 与 `taffy_expression_cnn_match` 已逐层透出 Q16 分母。`score_divider` 按 `round(100×65536/denominator)` 算出 0~100 的百分比，`score_text` 渲染成"得分 0.87"。

三份模块已通过 iverilog 语法检查、字形预览正确，但**尚未实例化进显示路径**，因此不占用本次综合的任何资源，也不影响烧录文件。

---

## 九、参考

- 原工程说明：`README_CNN.md`、`CACHE_FIX.md`、`CANNY_IMPLEMENTATION.md`、`EXPRESSION_RECOGNITION.md`、`PHOTO_RECOGNITION.md`
- 开发板资料索引：`BOARD_REFERENCES.md`
- 本次构建报告：`outflow_cnn/ti60f225_oob.map.rpt`、`.place.rpt`、`.timing.rpt`、`.hier_util.rpt`
