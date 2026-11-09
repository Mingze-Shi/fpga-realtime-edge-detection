# Ti60 四类脸部表情图案识别

## 本次实现

在原 sobel_filter1028 工程上增加四类脸部图案分类。采用 4 bit 灰度、分区域 SAD 模板比较、亮度均值补偿和 5×5 小范围平移搜索，不采用 CNN 或 TinyYOLO，不存在神经网络训练或预训练权重。依据是目前只有四张不同的参考图，目标是这些固定图案的区分，而且原包布局报告已经使用 248/256 个 RAM10。

类别编号：0 为无法确定，1 为露齿笑，2 为放松，3 为哭泣，4 为睁眼张嘴。名称是图案标签，不代表心理情绪判断。参考图来自队友聊天附件；带红圈的第四张只作为任务说明，未进入模板。

这是限定场景的模板分类器：操作者需要把眼睛和嘴巴对准固定检测框。没有实现自动找脸、多人物检测、任意尺度/角度识别，也不能把识别这几张图案等同于通用人物身份或表情识别。

## 开发板使用

1. 使用本包新生成的 outflow_expression/ti60f225_oob.bit（临时 JTAG 下载）或同目录 .hex（Flash 配置）。本次交付没有操作开发板或 Flash。原 outflow_canny 和其他 firmware 目录是保留的历史文件，不是本次新固件。
2. 复位后短按 SW3 一次进入原有彩色/红色边缘显示模式，同时启用表情分类。把参考图的眼睛与嘴巴区域对准中央横向长方框，不需要把整个人物、衣服或头顶放进框内。
3. 1920×1080 输出下检测框为 x=704～1215，y=412～667，即 512×256。每隔 16 个水平像素、8 个垂直像素采样一次，共 32×32 个点。实际操作可对照 assets/expressions/face_1.png 至 face_4.png，看清需要入框的区域。
4. 框呈黄色表示尚未形成有效结果，红色表示暂未确认，绿色表示同一类别连续三帧满足条件。屏幕显示对应中文标签，不能判断时显示无法确定。捕获帧结束、顺序扫描和显示帧边界提交会增加显示响应时间；不是按钮按下即刻确认。
5. 再短按 SW3 仍按原顺序切换至同帧冻结叠加、双帧回放以及原始显示模式。分类器只在模式 1 工作；离开模式会清除识别结果与连续确认计数。
6. SW1/SW2 的原有功能不变：非回放模式下边缘阈值按 8 增减；双帧回放模式下切换保留帧。识别门槛与 Canny 阈值分开，SW1/SW2 不调分类门槛。长按 SW3 的原有冻结/刷新逻辑保留。

## 数据和算法

- 原图及任务聊天：assets/expressions/source/。四张干净参考图裁剪坐标记录在 assets/expressions/model.json；tools/expression_model.py 中的 CLASSES 是可编辑来源。
- 特征：每张脸部参考图离线缩至 32×32，灰度右移四位。FPGA 对对齐后的画面直接按固定坐标采样，灰度转换保持原工程的 (77R+150G+29B+128)>>8。
- 模板：四张 32×32×4 bit，总计 16384 bit。实时采样使用两份 32×32×4 bit 乒乓存储，共 8192 bit。模板均值也由脚本生成并更新 RTL 常数。
- 比较：限定相同空间布局的眼部与嘴部区域，共 700 个点。所有区域共同采用同一个平移偏移，逐点计算 abs(输入-模板-输入均值+模板均值)，用一套电路依次检查四类和每类 25 个偏移。
- 拒识：灰度动态范围至少 3 个量化级；最佳误差不超过 1100；次佳误差与最佳误差差值至少 70。所有参数均是当前工程规则，不是概率或准确率。连续三帧必须是同一类别，否则计数重启；缺样、乱序、禁用和复位均清除结果。
- 所有类别都比较完才选择，不再采用原有任意局部块先匹配即结束的规则。文字与框在显示帧边界提交，保持原 RGB/DE/HS/VS 九拍流水线。

在 148.5 MHz 时钟假设下，一次顺序比较约 204805 拍，计算耗时约 1.379 ms；这只包括比较引擎，不包含整帧采样、三帧确认、显示和其他系统延迟，也不是板级实测帧率。

## 生成、检查和构建

需要 Python 3、Pillow、包内的 Icarus Verilog，以及 Efinity 2026.1。普通 Python 环境首次可安装 Pillow：python -m pip install pillow。

在当前工程根目录运行：

```powershell
python tools/expression_model.py
python tools/make_expression_text.py
python tests/run_all_tests.py
.\build_expressions.ps1 -EfinityBin 'D:\efinity\2026.1\bin'
```

build_expressions.ps1 先运行全部回归与新测试，再执行 map、interface、pnr；资源、时序和源文件新鲜度全部合格后才执行 pgm 生成配置文件。脚本不调用下载器。原 build_canny.ps1 在顶层启用 EXPRESSION_ENABLE 时转入该流程。

离线检查一个已经裁剪到相同脸部区域的图片：

```powershell
python tools/check_expression_frame.py assets/expressions/face_2.png
```

对于完整 1920×1080 RGB 显示帧，使用 --frame 按与 RTL 一致的固定坐标取样；如果输入尺寸不同，通过 --roi X Y STEP_X STEP_Y 指定，不会自动定位人脸。

```powershell
python tools/check_expression_frame.py your_display_frame.png --frame
```

## 测试证据和边界

原工程的 17 组回归测试覆盖按键、阈值、中值滤波、Sobel/彩色切换、冻结、完整 Canny 滞后连接、640×480 图像、同帧叠加和双帧回放，以及旧模板功能。新测试包含：

1. 69 个合成检查样例：四张原图的亮度、对比度、轻微模糊、±3°旋转、最多两格平移，以及空白、直线、噪声、棋盘、渐变和严重遮挡。
2. RTL 对照 Python：逐个比对类别、最佳误差、次佳误差，不只检查最终类别。
3. 状态检查：同类三帧确认、换类重计数、未知输入、错序与缺样、扫描期间禁用、复位。
4. 视频检查：四类中文标签、未知标签、1080p 字形边界、检测框及 RGB 对齐、真实模式按键和九拍同步。

最终日志为 test_output/all_tests.log、expression_software_validation.json；最终资源/时序及固件哈希见 outflow_expression/expression_verification.json。

合成样例全部来自这四张参考图，没有提供独立真实摄像头测试集。合成测试通过不能解释成摄像头准确率，也不证明能拒绝所有其他动漫脸。板级实拍、光照、拍摄距离、缩放、旋转和相似图案误报仍需实际验证。不得把本实现称为已训练 CNN、TinyYOLO 或通用表情识别。

## 兼容性与修改范围

原摄像头、DDR、HDMI、按键、阈值、滤波、Canny、冻结和回放 HDL 保留。未修改顶层端口、引脚约束、供电配置或时钟约束。原 taffy_photo_match.v、模板和旧成功文字保留；将顶层 .EXPRESSION_ENABLE(1) 改为 0 并重新构建，可恢复旧单图案识别路径。

主要新增文件为 rtl/taffy_expression_match.v、rtl/taffy_expression_text.v、assets/expressions/、相关 Python 工具及测试。接入改动位于 sc431_sobel_video.v、ti60f225_oob_top.v 和工程 XML。工作副本与用户原始 ZIP 分离保存。
