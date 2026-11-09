# Original project audit

Working board image: `delivery_stream_canny/ti60f225_oob.bit`; its output has
been confirmed on the user's monitor after restoration. Flash was not changed.

Original sources examined: `baseline_backup/` in this workspace and the earlier
project `D:/Ti60_CNN` (read only). The backup is the earlier frame-map Canny
version, not a frozen source snapshot of the working streaming bitstream.

Verified comparisons:

- `ti60f225_oob.peri.xml` matches `D:/Ti60_CNN/ti60f225_oob.peri.xml` byte for
  byte: SHA256 `6c8b3cd388c6bc6786116c5b04d40cd5d0f2fb5199a2d780e36429bf9bcca9b0`.
- Effective LPF instance parameters match the earlier project's
  `outflow_autoplay/ti60f225_oob.lpf`: 7924 parameters, zero differences.
  File hashes differ because generated metadata/formatting differ.
- The current top differs from the backup top only by enabling
  `CANNY_STREAM_ENABLE(1)`. PLL reset assignments remain KEY0_N.
- Global reset release requires KEY0_N and all three selected PLL lock signals.
  LED bits have different purposes; "all lit" alone is not a reset diagnosis.
- The shipping-source manifest is stale relative to the streaming changes;
  its top/project hash mismatch alone does not establish corruption.

The pure-DVI candidate, independent-pattern candidate and filter5 candidate
all failed monitor tests, despite passing synthesis/routed timing. Each was
replaced with the working delivery image. None is a verified release.

`ti60f225_baseline_audit.xml` uses backup top/video/project sources for a
rebuild control. A byte-identical copy of the backup top is placed under rtl
to preserve its relative DDR include resolution. Remaining modules come from
the current tree; canny_frontend retains the original 3x3 default branch.
Thus this is an earlier-design control, not proof of bit-identical reproduction
of the working streaming delivery image.

Earlier-design rebuild completed: map/pnr/pgm PASS, pixel setup margin +0.931 ns, no negative path slack. Bitstream outflow_baseline_audit/ti60f225_oob.bit is 2871090 bytes. Hardware display status is pending user observation.
