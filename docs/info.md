<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works
This design is a memoryless, streaming GPU rasterizer that processes incoming 4-bit triangle vertices on-the-fly, calculates a bounding box to restrict the scanning zone, and uses three parallel Pineda edge cross-product execution lanes to instantly determine and stream fragment colors without requiring internal frame memory layout arrays.

## How to test
To test the processor, stream in three sets of coordinate pairs using the 8-bit input bus while pulsing the control latch pin high. Ensure vertex winding order is strictly Counter-Clockwise (CCW). Monitor the output data lines to observe valid pixel rendering patterns and verify the completion interrupt signal flag drops smoothly into the finished state.

## External hardware

List external hardware used in your project (e.g. PMOD, LED display, etc), if any
