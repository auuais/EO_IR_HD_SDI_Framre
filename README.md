# EO IR HDSDI LineBuffer Frame Size

Vivado project for the low-latency line-buffer variant of the combined EO + IR HD-SDI stack design.

## Target

- Vivado: 2025.2
- FPGA part: `xcku15p-ffve1517-2-i`
- Top module: `KintexTop_EO_IR_Combined_HD_SDI`
- Project file: `EO_IR_HDSDI_LineBuffer_FRAMESIZE.xpr`

## Supported Modes

- EO single line-buffered HD output: `0x07..0x0C`
- IR single: `0x00..0x05`, `0x0D..0x12`
- IR stack: `0x14`
- EO stack: `0x15`

## Architecture Notes

- No DDR is used in this design.
- EO single mode now crosses into the common HD render clock through a small streaming FIFO instead of a frame buffer or raw clock pass-through.
- IR single mode now renders the selected 540x480 grayscale image into the HD raster through a streaming FIFO instead of a full-frame buffer.
- EO stack mode uses per-camera streaming FIFOs instead of random-access frame buffers.
- EO stack preserves aspect ratio by sampling a centered 1440x1080 crop of each 1920x1080 EO input at 4-of-9 in Y and 4-of-9 source chroma pairs in X, producing 640x480 tiles while keeping Cb/Cr cadence.
- IR stack mode uses per-camera streaming line FIFOs, preserving aspect ratio by sampling a centered 576x512 crop at 15-of-16 in X/Y.
- IR stack uses zero-luma black padding to the right of the 3-column stack.
- EO still needs a vertical prefill before display because a 1080-line source is reduced into 480 output lines in the first half of the HD raster; that cannot be truly same-line latency without changing the layout/timing.
- Camera clock domains cross into the common render clock using async FIFOs where required.
- EO camera 0 uses a common-clock FIFO because its write clock and render clock share the same source; this avoids Vivado bitgen DRC failures on independent-clock structures with identical clocks.

## Build

The GUI project can be opened directly in Vivado. A non-project build script is also provided:

```tcl
source scripts/run_nonproject_bit.tcl
```

The known-good validation build completed with:

- Bitgen DRC errors: `0`
- Routed WNS: `0.628 ns`
- Routed WHS: `0.012 ns`
- Routed TNS: `0.000 ns`
- Routed resources: `5944 LUTs`, `7980 FFs`, `399 RAMB36`, `128 URAM`

Generated outputs are intentionally ignored by Git. Rebuild locally to regenerate bitstreams and reports.
