# FPGA-OV7670

## This project implements a **real-time video pipeline** on the Nexys A7-100T FPGA using an **OV7670 camera** as the video source. The live image is captured, buffered in BRAM, processed through optional filters, and displayed via **VGA output**.

![DEMO](OV7670_Demo.png)

## Features
- **Live video** from OV7670 camera (RGB444 @ 640×480)
- **VGA output** at 25.175 MHz pixel clock
- **I²C configuration** sequencer for OV7670 (RGB444 mode)
- **Real-time filters**:
  - Grayscale (BT.601 / BT.709 selectable)
  - Color inversion
  - Border overlay
- **Dual clock domain** design:
  - 24 MHz camera domain
  - 25.175 MHz VGA domain
- **Parameterizable frame buffer** using block RAM
- **Single-buffer streaming** (minimal latency)

## Controls (Nexys A7 Switches)
| Switch | Function |
|:-------|:----------|
| SW0 | Reserved (TPG select placeholder) |
| SW1 | Enable grayscale |
| SW2 | Use BT.709 coefficients |
| SW3 | Enable invert filter |
| SW4 | Enable border overlay |

## Future Improvements
- Add double-buffering to remove tearing
- Implement Sobel edge-detection filter
- Add UART debug interface for camera register updates
- Convert top module to parameterized video resolution
