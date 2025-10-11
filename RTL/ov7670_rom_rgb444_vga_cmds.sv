`timescale 1ns/1ps
`default_nettype none
import cam_i2c_pkg::*;

//   Initialization ROM for the OV7670 camera in RGB444 VGA mode (640x480).
//   Contains the full register write sequence used by the I2C sequencer.
//
// Source / References:
//   - Based on publicly available OV7670 register tables for RGB444 VGA mode
//     from:
//       * https://github.com/westonb/OV7670-Verilog
//   - The sequence has been adapted and verified for 24 MHz XCLK operation.

module ov7670_rom_rgb444_vga_cmds #(
    parameter int unsigned DLY_MS = 10,     // delay after reset (ms)
    parameter int unsigned N      = 77      // total entries including OP_END //77
)(
    output cam_i2c_pkg::cmd_t cmds [N]
);
    localparam op_t W = OP_WRITE;
    localparam op_t D = OP_DELAY;
    localparam op_t E = OP_END;

    // 0..1: reset + delay
    assign cmds[0]  = '{W, 8'h12, 8'h80, 16'd0};           // COM7: Reset SCCB registers
    assign cmds[1]  = '{D, 8'h00, 8'h00, 16'd10};          // Delay (legacy 0xFFF0)
    //assign cmds[2] =  '{W, 8'h42, 8'h08, 16'd0};           // enable color bars, must increase every index after
  
    assign cmds[2]  = '{W, 8'h12, 8'h04, 16'd0};           // COM7: RGB output
    assign cmds[3]  = '{W, 8'h11, 8'h00, 16'd0};           // CLKRC: internal PLL matches XCLK (24 MHz example)
    assign cmds[4]  = '{W, 8'h0C, 8'h00, 16'd0};           // COM3: default
    assign cmds[5]  = '{W, 8'h3E, 8'h00, 16'd0};           // COM14: no scaling, normal pclk
    assign cmds[6]  = '{W, 8'h04, 8'h00, 16'd0};           // COM1: CCIR656 disable
    assign cmds[7]  = '{W, 8'h8C, 8'h02, 16'd0};           // RGB444: enable RGB444 (xR GB)
    assign cmds[8]  = '{W, 8'h40, 8'hD0, 16'd0};           // COM15: full range for RGB 444  
  
    // 9..17: TSLB, COM9, matrix
    assign cmds[9]  = '{W, 8'h3A, 8'h04, 16'd0};           // TSLB: output sequence (byte order "magic")
    assign cmds[10] = '{W, 8'h14, 8'h18, 16'd0};           // COM9: MAX AGC x4
    assign cmds[11] = '{W, 8'h4F, 8'hB3, 16'd0};           // MTX1
    assign cmds[12] = '{W, 8'h50, 8'hB3, 16'd0};           // MTX2
    assign cmds[13] = '{W, 8'h51, 8'h00, 16'd0};           // MTX3
    assign cmds[14] = '{W, 8'h52, 8'h3D, 16'd0};           // MTX4
    assign cmds[15] = '{W, 8'h53, 8'hA7, 16'd0};           // MTX5
    assign cmds[16] = '{W, 8'h54, 8'hE4, 16'd0};           // MTX6
    assign cmds[17] = '{W, 8'h58, 8'h9E, 16'd0};           // MTXS

    // 18..26: COM13, window (H/V start/stop/ref), timing reset, mirror/flip
    assign cmds[18] = '{W, 8'h3D, 8'hC0, 16'd0};           // COM13: gamma enable
    assign cmds[19] = '{W, 8'h17, 8'h14, 16'd0};           // HSTART
    assign cmds[20] = '{W, 8'h18, 8'h02, 16'd0};           // HSTOP
    assign cmds[21] = '{W, 8'h32, 8'h80, 16'd0};           // HREF
    assign cmds[22] = '{W, 8'h19, 8'h03, 16'd0};           // VSTART
    assign cmds[23] = '{W, 8'h1A, 8'h7B, 16'd0};           // VSTOP
    assign cmds[24] = '{W, 8'h03, 8'h0A, 16'd0};           // VREF
    assign cmds[25] = '{W, 8'h0F, 8'h41, 16'd0};           // COM6: reset timings
    assign cmds[26] = '{W, 8'h1E, 8'h00, 16'd0};           // MVFP: no mirror/flip

    // 27..34: misc tuning
    assign cmds[27] = '{W, 8'h33, 8'h0B, 16'd0};           // CHLF
    assign cmds[28] = '{W, 8'h3C, 8'h78, 16'd0};           // COM12: no HREF when VSYNC low
    assign cmds[29] = '{W, 8'h69, 8'h00, 16'd0};           // GFIX
    assign cmds[30] = '{W, 8'h74, 8'h00, 16'd0};           // REG74: digital gain
    assign cmds[31] = '{W, 8'hB0, 8'h84, 16'd0};           // RSVD: color tweak (internet "magic")
    assign cmds[32] = '{W, 8'hB1, 8'h0C, 16'd0};           // ABLC1
    assign cmds[33] = '{W, 8'hB2, 8'h0E, 16'd0};           // RSVD
    assign cmds[34] = '{W, 8'hB3, 8'h80, 16'd0};           // THL_ST

    // 35..39: scaling / sample (placeholders per legacy set)
    assign cmds[35] = '{W, 8'h70, 8'h3A, 16'd0};           // SCALING_XSC
    assign cmds[36] = '{W, 8'h71, 8'h35, 16'd0};           // SCALING_YSC
    assign cmds[37] = '{W, 8'h72, 8'h11, 16'd0};           // SCALING DCWCTR
    assign cmds[38] = '{W, 8'h73, 8'hF0, 16'd0};           // SCALING PCLK_DIV
    assign cmds[39] = '{W, 8'hA2, 8'h02, 16'd0};           // SCALING PCLK DELAY

    // 40..55: gamma curve
    assign cmds[40] = '{W, 8'h7A, 8'h20, 16'd0};           // SLOP
    assign cmds[41] = '{W, 8'h7B, 8'h10, 16'd0};           // GAM1
    assign cmds[42] = '{W, 8'h7C, 8'h1E, 16'd0};           // GAM2
    assign cmds[43] = '{W, 8'h7D, 8'h35, 16'd0};           // GAM3
    assign cmds[44] = '{W, 8'h7E, 8'h5A, 16'd0};           // GAM4
    assign cmds[45] = '{W, 8'h7F, 8'h69, 16'd0};           // GAM5
    assign cmds[46] = '{W, 8'h80, 8'h76, 16'd0};           // GAM6
    assign cmds[47] = '{W, 8'h81, 8'h80, 16'd0};           // GAM7
    assign cmds[48] = '{W, 8'h82, 8'h88, 16'd0};           // GAM8
    assign cmds[49] = '{W, 8'h83, 8'h8F, 16'd0};           // GAM9
    assign cmds[50] = '{W, 8'h84, 8'h96, 16'd0};           // GAM10
    assign cmds[51] = '{W, 8'h85, 8'hA3, 16'd0};           // GAM11
    assign cmds[52] = '{W, 8'h86, 8'hAF, 16'd0};           // GAM12
    assign cmds[53] = '{W, 8'h87, 8'hC4, 16'd0};           // GAM13
    assign cmds[54] = '{W, 8'h88, 8'hD7, 16'd0};           // GAM14
    assign cmds[55] = '{W, 8'h89, 8'hE8, 16'd0};           // GAM15

    // 56..74: AGC/AEC block
    assign cmds[56] = '{W, 8'h13, 8'hE0, 16'd0};           // COM8: disable AGC/AEC
    assign cmds[57] = '{W, 8'h00, 8'h00, 16'd0};           // GAIN = 0
    assign cmds[58] = '{W, 8'h10, 8'h00, 16'd0};           // ARCJ = 0
    assign cmds[59] = '{W, 8'h0D, 8'h40, 16'd0};           // COM4: reserved bit
    assign cmds[60] = '{W, 8'h14, 8'h18, 16'd0};           // COM9: 4x gain + magic bit
    assign cmds[61] = '{W, 8'hA5, 8'h05, 16'd0};           // BD50MAX
    assign cmds[62] = '{W, 8'hAB, 8'h07, 16'd0};           // DB60MAX
    assign cmds[63] = '{W, 8'h24, 8'h95, 16'd0};           // AGC upper limit
    assign cmds[64] = '{W, 8'h25, 8'h33, 16'd0};           // AGC lower limit
    assign cmds[65] = '{W, 8'h26, 8'hE3, 16'd0};           // AGC/AEC fast mode op region
    assign cmds[66] = '{W, 8'h9F, 8'h78, 16'd0};           // HAECC1
    assign cmds[67] = '{W, 8'hA0, 8'h68, 16'd0};           // HAECC2
    assign cmds[68] = '{W, 8'hA1, 8'h03, 16'd0};           // magic
    assign cmds[69] = '{W, 8'hA6, 8'hD8, 16'd0};           // HAECC3
    assign cmds[70] = '{W, 8'hA7, 8'hD8, 16'd0};           // HAECC4
    assign cmds[71] = '{W, 8'hA8, 8'hF0, 16'd0};           // HAECC5
    assign cmds[72] = '{W, 8'hA9, 8'h90, 16'd0};           // HAECC6
    assign cmds[73] = '{W, 8'hAA, 8'h94, 16'd0};           // HAECC7
    assign cmds[74] = '{W, 8'h13, 8'hA7, 16'd0};           // COM8: enable AGC/AEC
    assign cmds[75] = '{W, 8'h69, 8'h06, 16'd0};           // 
    // 76: end
    assign cmds[76] = '{E, 8'h00, 8'h00, 16'd0};           // OP_END

endmodule
`default_nettype wire
