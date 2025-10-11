`timescale 1ns/1ps

import video_pkg::*;
import cam_pkg::*;
import cam_i2c_pkg::*;

// Description:
//   Top-level integration of the OV7670 camera capture, frame buffer, and VGA
//   display pipeline. This design generates live video output on VGA with
//   optional real-time filters controlled by on-board switches.
//
//   The camera (OV7670) is configured via I2C at startup, streams pixel data
//   into a dual-port BRAM acting as a frame buffer, and the VGA logic reads
//   those pixels out in sync with the display timing. The system operates with
//   two clock domains: 24 MHz for the camera and 25.175 MHz for the VGA output.
//
// Video Path:
//   OV7670 -> cam_capture_data -> dual_port_BRAM -> camera_pixels -> filters
//           -> VGA output (R, G, B, HSYNC, VSYNC)
//
// Filters (controlled by SW):
//   SW[1] - Enable grayscale
//   SW[2] - Use BT.709 grayscale coefficients
//   SW[3] - Enable color inversion
//   SW[4] - Enable border overlay
//
// Parameters:
//   T  - Video timing structure (default: 640×480@60Hz).
//   TH - Border thickness in pixels.
//   BC - Border color (3-bit RGB).
//
// Features:
//    I2C initialization of the OV7670 using sequencer and ROM commands
//    Dual clock domain design with synchronized resets
//    Frame buffering via block RAM 
//    Modular filter chain 
//    Configurable pixel processing pipeline with adjustable latency
//
// Notes:
//   Minor tearing during fast motion is expected with a single buffer.
//   PIPE_LAT compensates HS/VS timing to align with RGB latency.
//   Can be extended with double buffering or additional image filters.

module top_tpg_vga 
#(
    parameter video_pkg::vid_timing_t T = video_pkg::TIMING_VGA_640x480, 
    parameter int TH = 2,                                                        // border width
    parameter logic [2:0] BC = 3'b101                                            // border color
)
(
    input logic                         clk,
    input logic                         RST,
    input logic [4:0]                   SW,
    input logic                         BTN, CTRL_BTN,
    output logic [video_pkg::RGBW-1:0]  VGA_R,
    output logic [video_pkg::RGBW-1:0]  VGA_G,
    output logic [video_pkg::RGBW-1:0]  VGA_B,
    output logic                        VGA_HS, VGA_VS,
    output logic                        locked_led,
    
    // These are for the camera
    input logic                         CAM_PCLK,               // camera pixel clock
    input logic                         CAM_VSYNC, CAM_HREF,
    input logic  [7:0]                  CAM_D,                  // data byte
    output logic [2:0]                  STATE,
    output logic                        PID_FLAG, VER_FLAG, BTN_LEVEL,
    output logic                        CAM_RSTN, CAM_PWDN,
    output logic                        CAM_XCLK,              // 24.0 mhz
    inout  tri                          CAM_SCL, CAM_SDA
    
);
    
    localparam int N_SW = $bits(SW);
    localparam int N_BTN = $bits(BTN);
    
    localparam PACKED_DW   = $bits(video_pkg::video_word_t);
    localparam CAM_DW      = 8;
    localparam FIFO_AW     = 4;
    
    // SW0 = src_sel(tpg/camera), SW1 = en_greyscale, SW2 = gs_bt709, SW3 = en_invert, SW4 = en_border
    logic [N_SW-1:0] sync_sw;
    logic [N_BTN-1:0] sync_btn;
    
    logic RST_N;
    assign RST_N = ~RST;
    
    logic pix_clk;      // 25.175 MHz
    logic mmcm_locked;
    
    
clk_wiz_pixcam 
    u_clk
    (
        .clk_in1(clk),
        .reset(RST),
        .clk_out1(pix_clk),
        .clk_out2(CAM_XCLK),
        .locked(mmcm_locked)
        );

    assign  CAM_PWDN = 0;
    assign  CAM_RSTN = 1;
    
    // I2C configuration chain (OV7670 RGB444)
    localparam int N_CMDS = 77; // 77 b4
    cam_i2c_pkg::cmd_t init_cmds [N_CMDS];
    
ov7670_rom_rgb444_vga_cmds #(
        .DLY_MS(10),
        .N(N_CMDS)
    ) u_rom (
        .cmds(init_cmds)
    );
    
    // simple one-shot start after reset+lock
    logic cfg_start;
    logic [2:0] cfg_sync;
    always_ff @(posedge clk or negedge RST_N) begin
        if (!RST_N)             cfg_sync <= 3'b000;
        else if (!mmcm_locked)  cfg_sync <= 3'b000;
        else                    cfg_sync <= {cfg_sync[1:0], 1'b1};
    end
    assign cfg_start = (cfg_sync == 3'b011); // 1-cycle pulse when lock syncs in
    
    // optional 1ms tick (since USE_TICK=1 below)
    logic tick_1ms;
    localparam int MS_DIV = (100_000_000 + 999) / 1000;
    logic [$clog2(MS_DIV)-1:0] ms_cnt;
    always_ff @(posedge clk or negedge RST_N) begin
        if (!RST_N) begin
            ms_cnt   <= '0;
            tick_1ms <= 1'b0;
        end else if (ms_cnt == MS_DIV-1) begin
            ms_cnt   <= '0;
            tick_1ms <= 1'b1;
        end else begin
            ms_cnt   <= ms_cnt + 1'b1;
            tick_1ms <= 1'b0;
        end
    end
    
    // sequencer adapter signals
    logic       wr_start, wr_done, wr_busy, wr_ackerr;
    logic [6:0] wr_dev_addr7;
    logic [7:0] wr_reg, wr_val;
    logic       seq_busy, seq_done, seq_err;
    
cam_i2c_sequencer #(
        .CLK_HZ(100_000_000),
        .USE_TICK(0),                 // we provide tick_1ms
        .DEV_ADDR7(7'h21),            // OV7670 write address (0x42 >> 1)
        .N_CMDS(N_CMDS),
        .MAX_RETRIES(3)
    ) u_seq (
        .clk      (clk),
        .rst_n    (RST_N),
        .start    (cfg_start),
        .busy     (seq_busy),
        .done     (seq_done),   // initialization is done
        .error    (seq_err),
        .tick_1ms (1'b0),       // using internal counter
        .cmds     (init_cmds),
        
        .wr_start     (wr_start),
        .wr_dev_addr7 (wr_dev_addr7), // comes from sequencer (it outputs DEV_ADDR7)
        .wr_reg       (wr_reg),
        .wr_val       (wr_val),
        .wr_busy      (wr_busy),
        .wr_done      (wr_done),
        .wr_ackerr    (wr_ackerr)
    );
    
    // byte-writer adapter that uses your existing i2c_master
i2c_controller #(
        .SYS_CLK   (100_000_000),
        .I2C_SPEED (100_000),
        .STRETCH_EN(1)
    ) u_i2c (
        .clk          (clk),
        .rst_n        (RST_N),
        .wr_start     (wr_start),
        .wr_dev_addr7 (wr_dev_addr7), // from sequencer
        .wr_reg       (wr_reg),
        .wr_val       (wr_val),
        .wr_busy      (wr_busy),
        .wr_done      (wr_done),
        .wr_ackerr    (wr_ackerr),
        .sda_io       (CAM_SDA),
        .scl_io       (CAM_SCL)
    );
    

    // robust pixel-domain reset: hold in reset until LOCKED, then deassert sync'd
    logic [2:0] pix_rst_sync;
    logic rst_pix_n;
    always_ff @(posedge pix_clk or negedge RST_N) begin
      if (!RST_N)         pix_rst_sync <= 3'b000;
      else if (!mmcm_locked) pix_rst_sync <= 3'b000;        // re-hold if MMCM loses lock
      else                pix_rst_sync <= {pix_rst_sync[1:0], 1'b1};
    end
    assign rst_pix_n = pix_rst_sync[2];  

    assign locked_led = mmcm_locked;
    
    // timing
    localparam int XW = $clog2(T.H_ACTIVE);
    localparam int YW = $clog2(T.V_ACTIVE);
    logic [XW-1:0] x_pos;
    logic [YW-1:0] y_pos;
    logic de;
    
csr_sync
    #(
        .N_SW(N_SW),
        .N_BTN(N_BTN)
    )
    csr
    (
        .clk(pix_clk),
        .rst_n(rst_pix_n),
        .async_sw(SW),
        .async_btn(BTN),
        .sync_sw(sync_sw),
        .sync_btn(sync_btn) 
    );
    
    // In top, next to your sb0 wiring
    logic  en_grey_req, sel709_req, en_inv_req, en_border_req;
   // assign en_camera_req = sync_sw[0];
    assign en_grey_req   = sync_sw[1];
    assign sel709_req    = sync_sw[2];
    assign en_inv_req    = sync_sw[3];
    assign en_border_req = sync_sw[4];
    
    localparam FB_DEPTH = T.H_ACTIVE * T.V_ACTIVE;
    localparam FB_AW        = $clog2(FB_DEPTH);  
    
    pixel_t             packed_rgb;
    pixel_t             unpacked_rgb;
    
    logic               wr, rd;
    logic [FB_AW-1:0]   waddr, raddr;

// Write-side reset: sync to CAM_PCLK (active-low)
    logic wrst_n, rrst_n;
    always_ff @(posedge CAM_PCLK or negedge RST_N)
        if (!RST_N) wrst_n <= 1'b0;
        else        wrst_n <= 1'b1;
    
    assign rrst_n = rst_pix_n;

cam_capture_data
    #( 
        .CAM_DW(CAM_DW),
        .RGB565(0)                // zero = RGB444, one = RGB565, rest of the most coming soon                                    
    )
    camera_data
    (
        .pclk(CAM_PCLK), .rst_n(RST_N),
        .i_cam_data(CAM_D),
        .i_vsync(CAM_VSYNC),
        .i_href(CAM_HREF),
        .i_init_done(seq_done),
        .addr(waddr),
        .wr(wr),
        .packed_rgb(packed_rgb)
    );
        
        
dual_port_BRAM 
    #(
        .DATA_BITS(12),
        .ADDR_W(FB_DEPTH)
    )
    frame_buffer
    (
        .wclk(CAM_PCLK), .rclk(pix_clk),
        .waddr(waddr), .raddr(raddr),
        .wr(wr), .rd(rd),
        .en(1'b1),
        .wdata(packed_rgb),
        .rdata(unpacked_rgb)
);

    logic hs_raw, vs_raw;

vga_timing
    #(
        .T(T)
    )
    timing
    (
        .PIX_CLK(pix_clk),
        .RST_N(rst_pix_n), 
        .DE(de),
        .HSYNC(hs_raw),
        .VSYNC(vs_raw),
        .X_POS(x_pos),
        .Y_POS(y_pos)
    );

    // total registered latency through the pixel pipeline
    localparam int PIPE_LAT =  7; // 1 (CAMERA) + 4 (GREY) + 1 (INV) + 1 (BORDER)
    
    // shift-register delay for HS/VS to match RGB latency
    logic [PIPE_LAT-1:0] hs_sr, vs_sr;
    always_ff @(posedge pix_clk or negedge rst_pix_n) begin
      if (!rst_pix_n) begin
        hs_sr <= '0;
        vs_sr <= '0;
      end else begin
        hs_sr <= {hs_sr[PIPE_LAT-2:0], hs_raw};
        vs_sr <= {vs_sr[PIPE_LAT-2:0], vs_raw};
      end
    end

      //sideband interface bundle
     vid_sideband_if #(.XW(XW), .YW(YW)) sb0 ();
     vid_sideband_if #(.XW(XW), .YW(YW)) sb1 ();
     vid_sideband_if #(.XW(XW), .YW(YW)) sb2 ();
     vid_sideband_if #(.XW(XW), .YW(YW)) sb3 ();
     vid_sideband_if #(.XW(XW), .YW(YW)) sb4 ();
    
    //Drive sb0 from timing module
    assign sb0.de = de;
    assign sb0.x  = x_pos;
    assign sb0.y  = y_pos;

    assign sb0.sof = de && (x_pos == '0) && (y_pos == '0);
    assign sb0.eol = de && (x_pos== T.H_ACTIVE-1); 
  
    pixel_t pix_cam;
    pixel_t pix_tpg;
    pixel_t pix_grey;
    pixel_t inv_out;
    pixel_t border_out;

camera_pixels 
    #(
        .BLACK_ON_UNDERRUN(0),   // 1: drive black + DE =0 when empty during DE
        .ADDR_W(FB_AW)
    )
    fifo_vga_bridge
    (
        .clk(pix_clk), .rst_n(rst_pix_n),    
        .rd(rd),         
        .vga_addr(raddr),
        .px_in(unpacked_rgb),   // read data
        .px_out(pix_cam),    
        .sb_in(sb0),
        .sb_out(sb1)
    );
    
     
filt_greyscale
    #(
        .XW(XW),
        .YW(YW)
    )
    greyscale_filter
    (
        .clk(pix_clk),
        .rst_n(rst_pix_n),
        .ctrl({sel709_req,en_grey_req}), //sync_sw[2:1]
        .px_in(pix_cam),
        .px_out(pix_grey),
        .sb_in(sb1),
        .sb_out(sb2)
    );

filt_invert
    invert_filter
    (
        .clk(pix_clk),
        .rst_n(rst_pix_n),
        .en(en_inv_req), //sync_sw[3]
        .px_in(pix_grey),
        .px_out(inv_out),
        .sb_in(sb2),
        .sb_out(sb3)
    );
    
 filt_border
    #(
        .T(T),
        .TH(TH), //border thickness
        .BC(BC) // Border Color
    )
    border_filter
    (
         .clk(pix_clk),
         .rst_n(rst_pix_n),
         .en(en_border_req),//sync_sw[4]
         .px_in(inv_out),
         .px_out(border_out),
         .sb_in(sb3),
         .sb_out(sb4)
    );
    
    // drive the pins with delayed syncs
    assign VGA_HS = hs_sr[PIPE_LAT-1];
    assign VGA_VS = vs_sr[PIPE_LAT-1];
    
    assign VGA_R = sb4.de? border_out.R : '0;
    assign VGA_G = sb4.de? border_out.G : '0;
    assign VGA_B = sb4.de? border_out.B : '0;

endmodule