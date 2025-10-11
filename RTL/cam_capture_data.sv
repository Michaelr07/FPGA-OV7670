`timescale 1ns / 1ps
`default_nettype none

import video_pkg::*;

// Camera Capture Module (OV7670 Compatible)
// Collects pixel data and generates RGB444 or RGB565 pixels.
//
// Features:
//   Handles VSYNC/HREF synchronization
//   Skips first frame after camera init for stabilization
//   Outputs valid pixel_t + write enable for FIFO/memory

module cam_capture_data
#(
    parameter video_pkg::vid_timing_t T = video_pkg::TIMING_VGA_640x480,
    parameter int CAM_DW  = 8,
    parameter bit RGB565   = 0
)
(
    input  wire logic                                   pclk,
    input  wire logic                                   rst_n,
    input  wire logic [CAM_DW-1:0]                      i_cam_data,
    input  wire logic                                   i_vsync,
    input  wire logic                                   i_href,
    input  wire logic                                   i_init_done,

    output logic [$clog2(T.H_ACTIVE*T.V_ACTIVE)-1:0]    addr,
    output logic                                        wr,
    output pixel_t                                      packed_rgb
);

    // Reset Synchronizer
    logic [1:0] rst_sync;
    logic rst_pclk;
    always_ff @(posedge pclk or negedge rst_n)
        if (!rst_n) rst_sync <= 2'b00;
        else        rst_sync <= {rst_sync[0], 1'b1};

    assign rst_pclk = ~rst_sync[1];

    // VSYNC / HREF Edge Detection
    logic vsync_d1, vsync_d2;
    logic href_d1,  href_d2;
    logic sof, eof, eol;

    always_ff @(posedge pclk) begin
        if (rst_pclk) begin
            {vsync_d2, vsync_d1} <= '0;
            {href_d2,  href_d1 } <= '0;
        end else begin
            {vsync_d2, vsync_d1} <= {vsync_d1, i_vsync};
            {href_d2,  href_d1 } <= {href_d1,  i_href };
        end
    end

    assign sof =  vsync_d2 & ~vsync_d1; // VSYNC falling = start of frame
    assign eof = ~vsync_d2 &  vsync_d1; // VSYNC rising  = end of frame
    assign eol =  href_d2  & ~href_d1;  // HREF falling  = end of line

    // Byte Phase Tracking
    logic [7:0] byte_1;
    logic byte_phase;

    always_ff @(posedge pclk)
        if (rst_pclk || !i_href)
            byte_phase <= 1'b0;
        else
            byte_phase <= ~byte_phase;

    // Optional: Skip first frame after init (OV7670 warm-up)
    logic skip_frame;
    always_ff @(posedge pclk or posedge rst_pclk)
        if (rst_pclk)
            skip_frame <= 1'b1;
        else if (eof && i_init_done)
            skip_frame <= 1'b0;

    // FSM: Capture and Pixel Packing
    typedef enum logic [1:0] {IDLE, CAPTURE, FRAME_DONE} state_t;
    state_t state, next;

    always_ff @(posedge pclk)
        if (rst_pclk) state <= IDLE;
        else          state <= next;

    always_comb begin
        next = state;
        case (state)
            IDLE       : if (sof && i_init_done && !skip_frame) next = CAPTURE;
            CAPTURE    : if (eof)                               next = FRAME_DONE;
            FRAME_DONE : if (sof)                               next = CAPTURE;
            default    : next = IDLE;
        endcase
    end

    // Capture Logic
    always_ff @(posedge pclk) begin
        if (rst_pclk) begin
            byte_1     <= '0;
            packed_rgb <= '0;
            addr       <= '0;
            wr         <= 1'b0;
        end else begin
            wr <= 1'b0;
            if (sof) addr   <= '0;
            
            if (state == CAPTURE && i_href) begin
                if (!byte_phase)
                    byte_1 <= i_cam_data;
                else begin
                    wr      <= 1'b1;
                    addr    <= addr + 1;
                    if (!RGB565) begin
                        // RGB444: {R[3:0], G[3:0], B[3:0]}
                        packed_rgb.R <= byte_1[3:0];
                        packed_rgb.G <= i_cam_data[7:4];
                        packed_rgb.B <= i_cam_data[3:0];
                    end else begin
                        // RGB565
                        packed_rgb.R <= byte_1[7:3];
                        packed_rgb.G <= {byte_1[2:0], i_cam_data[7:5]};
                        packed_rgb.B <= i_cam_data[4:0];
                    end
                end
            end
        end
    end
    

endmodule

`default_nettype wire
