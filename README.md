# EO IR HDSDI BRAM-URAM Frame Size

Vivado project for the BRAM/UltraRAM fallback design that combines the previously stable EO stack and IR stack functionality without DDR.

## Target

- Vivado: 2025.2
- FPGA part: `xcku15p-ffve1517-2-i`
- Top module: `KintexTop_EO_IR_Combined_HD_SDI`
- Project file: `EO_IR_HDSDI_BRAM-URAM_FRAMESIZE.xpr`

## Supported Modes

- EO single direct pass-through: `0x07..0x0C`
- IR single: `0x00..0x05`, `0x0D..0x12`
- IR stack: `0x14`
- EO stack: `0x15`

## Architecture Notes

- No DDR is used in this design.
- EO stack stores 640x480 tiles for each camera, packing the 8-bit Y/C samples into 16-bit BRAM entries and restoring the 20-bit output word on read.
- EO stack preserves aspect ratio by sampling a centered 1440x1080 crop of each 1920x1080 EO input at 4-of-9 in Y and 4-of-9 source chroma pairs in X, producing 640x480 tiles while keeping Cb/Cr cadence.
- IR stack stores 540x480 tiles for each camera, preserving aspect ratio by sampling a centered 576x512 crop at 15-of-16 in X/Y.
- IR stack uses zero-luma black padding to the right of the 3-column stack.
- Camera clock domains cross into the common render clock using async FIFOs where required.
- EO camera 0 bypasses the async FIFO because its write clock and render clock share the same source; this avoids Vivado bitgen DRC failures on independent-clock FIFO usage with identical clocks.

## Build

The GUI project can be opened directly in Vivado. A non-project build script is also provided:

```tcl
source scripts/run_nonproject_bit.tcl
```

The known-good validation build completed with:

- Bitgen DRC errors: `0`
- Routed WNS: `0.511 ns`
- Routed TNS: `0.000 ns`

Generated outputs are intentionally ignored by Git. Rebuild locally to regenerate bitstreams and reports.
