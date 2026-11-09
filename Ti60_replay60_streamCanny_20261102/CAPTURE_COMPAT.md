# Capture compatibility candidate

Observed: the capture device accepts a computer using the same HDMI cable;
Ti60 displays 1080p60 on a monitor, but captures black. The exact incompatibility
has not been established.

This candidate replaces only the final encrypted HDMI encoder with a pure-video
DVI/TMDS encoder. The camera, DDR, Canny, output clock, pin assignments and
serialization remain the existing design. It deliberately sends no audio or HDMI
data islands. DVI input support depends on the capture device; this is a diagnostic
candidate, not a confirmed repair.

Project: `ti60f225_capture_compat.xml`; copied top:
`rtl/ti60f225_capture_compat_top.v`; encoder: `rtl/capture_dvi_compat.v`.
The original top and project remain available for rollback. Future edits to the
original top must also be ported to the copied top.

Build with `build_capture_compat.ps1`. Review timing before running the pgm flow.
Only test via volatile JTAG first; no Flash programming has been performed.

Encoder testbench: `tests/capture_tmds_tb.v` checks all four control symbols,
4096 pixel decode round trips and the running disparity bound. The bundled
Icarus executable currently fails to start with a Windows DLL relocation error;
these simulation tests have not been run.

The compatibility encoder registers RGB and DE/HS/VS together before TMDS encoding to isolate the overlay combinational path. The first unregistered candidate failed setup by 0.173 ns and was not programmed.

Build result: map/interface/pnr/pgm PASS. Pixel-domain setup slack +1.596 ns; all reported clock relationship setup and hold margins positive. Volatile JTAG load succeeded on Ti60 ID 0x10660A79. OBS still displayed capture-card color bars after activation; compatibility is NOT confirmed. Next check: monitor output with this volatile image, without powering the board off.

Board test FAILED: monitor flickers without a stable picture on the pure DVI candidate. Original delivery_stream_canny bitstream was restored successfully via volatile JTAG. Do not use this candidate as a working fix.

Second diagnostic: ti60f225_capture_pattern.xml uses the original encrypted HDMI encoder with a free-running 2200x1125 1080p60 test pattern. Generated outflow_capture_pattern/ti60f225_oob.bit; map/pnr/pgm passed, reused unchanged periphery outputs, pixel setup +2.612 ns, no negative reported path slack. The rightmost bar is dark gray to distinguish it from capture-card no-signal bars. This is a diagnostic image, not the camera adaptation.

Second board test FAILED: monitor reports no output with original encoder plus independent pattern. Original delivery_stream_canny bitstream restored again successfully via JTAG. Neither diagnostic image is a working adaptation; baseline reproducibility and reset/serializer integration must be validated before further adaptation.
