`timescale 1ns / 1ps
`default_nettype none

//   BRAM-to-VGA read bridge that converts sequential frame buffer data into a
//   pixel stream synchronized with VGA timing signals
//
//   This module handles the 1-cycle latency of synchronous BRAM reads by
//   delaying the video sideband (DE/SOF/EOL/x/y) by one clock cycle so that
//   each pixel output aligns perfectly with its timing metadata
//
//   It also includes a "look-ahead" address generator to eliminate the 
//   one-pixel wraparound artifact
//
// Parameters:
//   T                  Video timing structure (default: VGA 640×480@60Hz)
//   BLACK_ON_UNDERRUN  Drive black pixels instead of stale data if empty
//   ADDR_W             Address width for the frame buffer

import video_pkg::*;

module camera_pixels #(
    parameter video_pkg::vid_timing_t T = video_pkg::TIMING_VGA_640x480,
    parameter bit BLACK_ON_UNDERRUN = 1,
    parameter int ADDR_W = $clog2(T.H_ACTIVE * T.V_ACTIVE)
)(
    input  wire logic               clk, rst_n,
    // BRAM read controls
    output      logic               rd,
    output      logic [ADDR_W-1:0]  vga_addr,
    // BRAM read data (already 1-cycle late from addr/rd)
    input       pixel_t             px_in,
    // Output to downstream VGA pipeline
    output      pixel_t             px_out,
    vid_sideband_if.sink            sb_in,
    vid_sideband_if.source          sb_out
);

    // Look-ahead address logic to avoid 1-pixel wrap
    logic [ADDR_W-1:0] addr_q, addr_next;
    
    always_comb begin
        addr_next = addr_q;
        if (sb_in.sof)
            addr_next = '0;              
        else if (sb_in.de)
            addr_next = addr_q + 1'b1;      // increment during active video
    end
    
    // Feed the BRAM its next address immediately
    assign vga_addr = addr_next;
    
    // Register the address for next-cycle reference
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            addr_q <= '0;
        else
            addr_q <= addr_next;
    end
    
    logic rd_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd   <= 1'b0;
            rd_q <= 1'b0;
        end else begin
            rd   <= sb_in.de; 
            rd_q <= rd;     
        end
    end

    // Delay sideband by 1 to align with returned pixel
    // Capture incoming sideband so we can shift it by one cycle.
    typedef struct packed {
        logic de, sof, eol;
        logic [$bits(sb_in.x)-1:0] x;
        logic [$bits(sb_in.y)-1:0] y;
    } sb_t;

    sb_t sb_in_q, sb_in_qq;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sb_in_q  <= '0;
            sb_in_qq <= '0;
        end else begin
            sb_in_q.de  <= sb_in.de;
            sb_in_q.sof <= sb_in.sof;
            sb_in_q.eol <= sb_in.eol;
            sb_in_q.x   <= sb_in.x;
            sb_in_q.y   <= sb_in.y;

            // Second stage aligns with rd_q
            sb_in_qq <= sb_in_q;
        end
    end

    // Drive aligned sideband/pixels
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sb_out.de  <= 1'b0;
            sb_out.sof <= 1'b0;
            sb_out.eol <= 1'b0;
            sb_out.x   <= '0;
            sb_out.y   <= '0;
            px_out     <= '0;
        end else begin
            // Only assert DE on the aligned cycle when data is valid
            sb_out.de  <= rd_q;
            // SOF/EOL aligned one cycle later as well
            sb_out.sof <= sb_in_qq.sof & rd_q;
            sb_out.eol <= sb_in_qq.eol & rd_q;
            sb_out.x   <= sb_in_qq.x;
            sb_out.y   <= sb_in_qq.y;

            if (rd_q) begin
                if (!BLACK_ON_UNDERRUN)
                    px_out <= px_in;  // aligned BRAM pixel
                else
                    px_out <= '0;     // or force black when chosen
            end
        end
    end

endmodule

`default_nettype wire
