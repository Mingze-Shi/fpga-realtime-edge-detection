# 5x5 denoising for streaming Canny

The shipping `ti60f225_oob.xml` / `rtl/ti60f225_oob_top.v` path now uses:

`grayscale -> exact 5x5 median -> 5x5 Gaussian -> Sobel -> NMS -> thresholds -> local hysteresis`.

The median is the 13th of all 25 samples, implemented as a pipelined 32-way
bitonic network with seven 255 sentinels. It is not a median of row medians.
The Gaussian is the separable binomial kernel `[1,4,6,4,1]` in each direction,
normalised by 256 with round-to-nearest. Both run at one pixel per clock.

Median latency is 18 clocks; Gaussian latency is 4 clocks; streaming Canny
latency is 14 clocks (previously 13). RGB/grey delay taps grow by 15 clocks,
and the post-Sobel sync delay grows by one. Legacy non-streaming mode keeps
the previous 3x3 median and Gaussian, so its frontend reference remains usable.
The streaming hysteresis output also masks incomplete frame/line windows:
line RAM is not reset and otherwise can leak old-frame edge classifications.

Validation:

- `tests/filters5x5_tb.v`: PASS for exact median and Gaussian values, constant
  input, isolated impulse, salt noise, random image, four frame changes,
  incomplete windows, pixel gaps, coordinates and DE/HS/VS latency.
- `tests/canny_stream_tb.v`: PASS for horizontal and vertical steps and
  14-clock latency; each step produces a single-pixel-wide edge. The previous
  frame-head residual at output row zero is removed.
- Final place/route timing and programming artifact status are recorded below.

The bundled simulator requires its `Library/mingw-w64/bin` in PATH and an
absolute `-B .../Library/lib/ivl` argument. Efinity's bin supplies `zlib1.dll`.

Filter kernels suppress isolated noise, at the cost of smoothing small details.
No temporal filter or full-frame connected-component removal is added, and
threshold defaults are unchanged. The existing spatial overlay alignment is
not reworked in this change; temporal pipeline delays are extended together.
Hardware image quality still requires observation on the board.

Final build: map/pnr/pgm PASS; unchanged interface outputs reused. Pixel setup margin +1.343 ns; no negative path slack found in the routed report. Bitstream: outflow_filter5/ti60f225_oob.bit, 2938761 bytes, SHA256 9DD0A3D1D53302EE7BA445390C7D0F341C62E8981924CEC4310BB15FC807114A. Original delivery_stream_canny bitstream remains available for rollback.

Hardware test FAILED: user reports no display and all LEDs illuminated after loading the filter5 candidate. Simulation and routed timing PASS do not establish working board operation. Do not use this bitstream as a verified release. Restoring original delivery image via JTAG.

Follow-up: the user confirmed that reloading `delivery_stream_canny/ti60f225_oob.bit`
restores the picture. The failed candidate's placement report listed essential
clock, camera, DDR and key ports as unassigned, and its placement log explicitly
said these would be placed randomly. Regenerating the interface flow restored
the baseline IO summary (only unused `pll_inst4_RSTN` unassigned). A fresh PNR
and board test are required; the earlier timing results do not validate this fix.
`build_filter5.ps1` now rejects unexpected unassigned ports before generating
programming files.

Rebuilt after interface regeneration: PNR and PGM PASS; setup minimum +0.167 ns, hold minimum +0.026 ns. New bitstream is 2,948,040 bytes. JTAG programming returned success (device 0x10660A79). Display and image-quality confirmation pending; see outflow_filter5/programming_record.json. Previous 2,938,761-byte bitstream is superseded.

## Spatial edge cleanup

The streaming hysteresis now requires at least two non-background neighbours for both strong and weak centre pixels. Weak centres still require a strong neighbour. Previously every strong centre survived even if isolated. This uses the existing 3x3 class window and adds no pipeline clocks or line RAM. Endpoints may be shortened; supported noise clusters and coherent frame-to-frame contour motion can still survive. This is spatial cleanup, not temporal stabilization.

Regression: filters5x5_tb and canny_stream_tb PASS (14 clocks). canny_cleanup_tb checks isolated pixels, two-pixel specks, horizontal/vertical/diagonal lines, corners, T junctions, weak-only contours, connected weak contours and background gaps. PASS. Current build and physical image quality are pending.

Cleanup build: map/interface/PNR/PGM PASS. Minimum setup +0.449 ns, hold +0.026 ns. JTAG SRAM download PASS. Bitstream 2,917,983 bytes, SHA256 2C2404DA920F51BE82634108CC8859919C22234D7CAE36046A788641C2935ECC. Physical display/noise evaluation pending. Prior user-confirmed working 5x5 image retained in delivery_filter5_before_cleanup/.

## Stationary contour jitter: input noise reduction

User confirmed static objects still have moving contours after spatial cleanup. Top-level sharpening previously used 16'd95535, which truncates to 29999 (about 1.83 in Q2.14). Set it to 8192 (0.5) to reduce noise amplification before Canny. This also softens the colour image. Streaming Canny now starts at threshold 96 in both requested and active registers; legacy mode retains 32. Key steps remain 8. No temporal frame filter is implemented by these changes. Prior cleanup image is retained in delivery_filter5_cleanup/. Threshold-key and legacy threshold-video regressions PASS. New synthesis/interface PASS; routed timing and board validation pending.

User requested higher sharpening before the 0.5x candidate was downloaded. That low-sharpen candidate was built but NOT programmed. Restore the previous effective gain using the valid literal 16'd29999 (~1.83), rather than overflowing 16'd95535. Streaming default threshold 96 remains. Rebuilding; physical result pending.

Final higher-sharpen candidate: map/interface/PNR/PGM PASS, setup minimum +0.371 ns, hold minimum +0.027 ns. JTAG SRAM programming PASS. Gain=29999/16384, streaming threshold=96. Bitstream 2,908,299 bytes, SHA256 9E3F653537219DB871BFDABB6E30F114F97FB7B5A617DE4CF274411AE0AAA580. Display/image quality confirmation pending.

Higher-sharpen/threshold-96 candidate REJECTED: user reports processed picture all black. Restored delivery_filter5_before_cleanup/ti60f225_oob.bit via JTAG successfully. This retains 5x5 median/Gaussian, threshold 32, prior effective sharpening, and no new neighbour suppression. Source defaults restored to 32; neighbour cleanup now opt-in CLEANUP_ENABLE=1, default disabled. Source has not been rebuilt after this rollback; outflow_filter5 is NOT the active/recommended artifact. See active_programming_record.json. Physical confirmation of restoration pending.

At user request, restored the earlier fluctuating-edge version: delivery_filter5_cleanup/ti60f225_oob.bit (SHA256 2C2404DA920F51BE82634108CC8859919C22234D7CAE36046A788641C2935ECC). JTAG SRAM programming PASS. Defaults: 5x5 filters, threshold32, original effective sharpening29999, neighbour cleanup enabled. Source CLEANUP_ENABLE default restored to1 to match. No new build performed; active artifact is the backup, not outflow_filter5.

User clarified black checkerboard regions have noise and edges have spurs since later changes. Restored the earlier before-cleanup 5x5 baseline again (verified SHA256 8C4E35B6AC2175AF8220E61B27B0B55BE2D41611A0F3F19C58125B4052FB3651). JTAG PASS. CLEANUP_ENABLE default disabled again. Awaiting comparison of black checkerboard interior and edges; do not attribute the visual issue to a specific change without that comparison.

User explicitly requested fragment suppression restored. After interruption, resumed and verified cleanup backup hash, then successfully programmed delivery_filter5_cleanup/ti60f225_oob.bit through JTAG SRAM. Threshold32, original sharpening, 5x5 filters, cleanup enabled. Source default aligned. Current active image recorded in active_programming_record.json.

User identified the exact desired checkpoint by quoting the first successful isolated-edge-suppression download message. Restored runtime HDL text to that checkpoint: unconditional two-neighbour cleanup, threshold_keys original defaults (32), and original top-level sharpening literal16'd95535 (effective29999 due to16-bit truncation). Removed later CLEANUP_ENABLE parameter. Active JTAG image already matches checkpoint backup delivery_filter5_cleanup/ti60f225_oob.bit, SHA256 2C2404DA920F51BE82634108CC8859919C22234D7CAE36046A788641C2935ECC. No new download or build in this source-restore step.

Investigating jumping white pixels on black checkerboard: added canny_flat_video_tb full sc431 video integration (median5x5, Gaussian5x5, Canny, actual output sync) at96x40. Seven frames with level0/255/16/128, dark +/-2, +/-8 and +/-16 seeded pixel noise; random blanking pixels and unreset RAM across brightness transitions. All frames produced zero edge pixels and3840 output samples. This rules out false edges for these synthetic stimuli only; it does not validate board RAM behaviour, live input statistics or checkerboard edge ringing. Board image remains the selected cleanup backup; no new firmware download performed.

User requested permanent programming of the currently selected cleanup version. SPI Flash erase/write/readback verification PASS (Winbond W25Q64, JEDEC0xEF6017), followed by JTAG SRAM load PASS. Files: delivery_filter5_cleanup/ti60f225_oob.hex and .bit, hashes recorded in programming_filter5_cleanup_flash_record.json. Power-cycle boot verification still requires physical board confirmation. Threshold32, 5x5 median/Gaussian and isolated-edge suppression enabled; original sharpening retained.
