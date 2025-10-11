`timescale 1ns/1ps
import video_pkg::*;

module tb_filt_greyscale;
  // clock/reset
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk; // 100 MHz

  // DUT I/O
  logic [1:0] ctrl;
  pixel_t     px_in, px_out;
  vid_sideband_if sb_in();
  vid_sideband_if sb_out();

  // DUT
  filt_greyscale dut (
    .clk   (clk),
    .rst_n (rst_n),
    .ctrl  (ctrl),
    .px_in (px_in),
    .px_out(px_out),
    .sb_in (sb_in),
    .sb_out(sb_out)
  );

    localparam int XW = $clog2(640);
    localparam int YW = $clog2(480);
  // ---------------- Stimulus ----------------
  initial begin
    // init
    ctrl  = 2'b01; // enable grayscale (BT.601)
    px_in = '0;
    sb_in.de  = 0; sb_in.sof = 0; sb_in.eol = 0; sb_in.x = '0; sb_in.y = '0;

    // reset
    repeat (4) @(posedge clk);
    rst_n = 1;

    // wait a few cycles after reset so history is valid
    repeat (5) @(posedge clk);

    // start of frame pulse
    sb_in.sof <= 1; @(posedge clk); sb_in.sof <= 0;

    // drive one short line of 16 pixels
    for (int i=0; i<16; i++) begin
      @(posedge clk);
      sb_in.de  <= 1;
      sb_in.eol <= (i==15);
      sb_in.x   <= i;
      sb_in.y   <= 0;

      // single white pixel at x=0, else black
      if (i==0) begin
        px_in.R <= '1; px_in.G <= '1; px_in.B <= '1;
      end else begin
        px_in.R <= '0; px_in.G <= '0; px_in.B <= '0;
      end
    end
    @(posedge clk);
    sb_in.de  <= 0; sb_in.eol <= 0;

    // run a little longer
    repeat (20) @(posedge clk);
    $finish;
  end

  // ---------------- Console logging ----------------
  always @(posedge clk) if (sb_in.de)
    $display("%0t IN  x=%0d y=%0d  R=%0d G=%0d B=%0d",
             $time, sb_in.x, sb_in.y, px_in.R, px_in.G, px_in.B);

  always @(posedge clk) if (sb_out.de)
    $display("%0t OUT x=%0d y=%0d  R=%0d G=%0d B=%0d",
             $time, sb_out.x, sb_out.y, px_out.R, px_out.G, px_out.B);

  // ---------------- Simple 3-cycle checker ----------------
  typedef struct packed {logic de; logic [XW-1:0] x; logic [YW-1:0] y;} t_timing;
  t_timing tin_d0, tin_d1, tin_d2;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tin_d0 <= '{de:0,x:'0,y:'0};
      tin_d1 <= '{de:0,x:'0,y:'0};
      tin_d2 <= '{de:0,x:'0,y:'0};
    end else begin
      tin_d0 <= '{de:sb_in.de, x:sb_in.x, y:sb_in.y};
      tin_d1 <= tin_d0;
      tin_d2 <= tin_d1;
    end
  end

  always @(posedge clk) if (rst_n) begin
    if (sb_out.de !== tin_d2.de)
      $error("DE mismatch @%0t: out=%0b exp=%0b", $time, sb_out.de, tin_d2.de);
    if (sb_out.de && tin_d2.de) begin
      if (sb_out.x !== tin_d2.x || sb_out.y !== tin_d2.y)
        $error("X/Y mismatch @%0t: out=(%0d,%0d) exp=(%0d,%0d)",
               $time, sb_out.x, sb_out.y, tin_d2.x, tin_d2.y);
    end
  end

endmodule
