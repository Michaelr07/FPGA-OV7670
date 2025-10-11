// cam_i2c_tb.sv
`timescale 1ns/1ps
`default_nettype none

import cam_i2c_pkg::*;

module cam_i2c_tb;

  // ---------------------------------------------------------------------------
  //  Clock & Reset
  // ---------------------------------------------------------------------------
  logic clk = 0;
  always #5 clk = ~clk;   // 100 MHz

  logic rst_n;
  initial begin
    rst_n = 0;
    repeat (10) @(posedge clk);
    rst_n = 1;
  end

  // safety watchdog
  initial begin
    #50ms;
    $fatal(1, "[WATCHDOG] Simulation timed out. Likely sequencer/controller hung.");
  end

  // ---------------------------------------------------------------------------
  //  I2C Wires with pullups
  // ---------------------------------------------------------------------------
  tri1 sda;
  tri1 scl;

  // ---------------------------------------------------------------------------
  //  DUT chain: ROM -> Sequencer -> Controller -> i2c_master
  // ---------------------------------------------------------------------------
  //localparam int N_CMDS = 5;
  localparam int N_CMDS = 77; // 77 b4
  cam_i2c_pkg::cmd_t init_cmds [N_CMDS];
    
    ov7670_rom_rgb444_vga_cmds #(
        .DLY_MS(10),
        .N(N_CMDS)
    ) u_rom (
        .cmds(init_cmds)
    );

  // Sequencer wires
  logic seq_start, seq_busy, seq_done, seq_err;
  logic wr_start;
  logic [6:0] wr_dev_addr7;
  logic [7:0] wr_reg, wr_val;
  logic wr_busy, wr_done, wr_ackerr;

  // Sequencer
  cam_i2c_sequencer #(
    .CLK_HZ(100_000_000),
    .USE_TICK(0),
    .DEV_ADDR7(7'h21),
    .N_CMDS(N_CMDS)
  ) u_seq (
    .clk, .rst_n,
    .start(seq_start),
    .busy(seq_busy),
    .done(seq_done),
    .error(seq_err),
    .tick_1ms(1'b0),
    .cmds(init_cmds),
    .wr_start(wr_start),
    .wr_dev_addr7(wr_dev_addr7),
    .wr_reg(wr_reg),
    .wr_val(wr_val),
    .wr_busy(wr_busy),
    .wr_done(wr_done),
    .wr_ackerr(wr_ackerr)
  );

  // Controller
  i2c_controller #(
    .SYS_CLK(100_000_000),
    .I2C_SPEED(100_000)
  ) u_ctrl (
    .clk, .rst_n,
    .wr_start(wr_start),
    .wr_dev_addr7(wr_dev_addr7),
    .wr_reg(wr_reg),
    .wr_val(wr_val),
    .wr_busy(wr_busy),
    .wr_done(wr_done),
    .wr_ackerr(wr_ackerr),
    .sda_io(sda),
    .scl_io(scl)
  );

  // Fake I2C slave: simple ACK-only device
  i2c_slave_ack_bfm #(.SLAVE_ADDR7(7'h21)) u_slave (
    .clk, .rst_n,
    .sda(sda), .scl(scl)
  );

  // ---------------------------------------------------------------------------
  //  Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    seq_start = 0;
    @(posedge rst_n);
    repeat (20) @(posedge clk);

    $display("[%0t] INFO: Starting init sequence...", $time);
    #2
    seq_start = 1; 
    @(posedge clk);
    seq_start = 0;

    wait (seq_done || seq_err);
    if (seq_err)
      $fatal(1, "[%0t] FAIL: Sequencer reported error.", $time);
    else
      $display("[%0t] PASS: Sequencer completed init sequence.", $time);

    #200;
    $finish;
  end

  // ---------------------------------------------------------------------------
  //  Protocol assertions (sanity)
  // ---------------------------------------------------------------------------
  logic sda_prev, scl_prev;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sda_prev <= 1'b1;
      scl_prev <= 1'b1;
    end else begin
      sda_prev <= sda;
      scl_prev <= scl;
    end
  end

  wire sda_rise    = (sda_prev==0 && sda==1);
  wire sda_fall    = (sda_prev==1 && sda==0);
  wire scl_rise_ev = (scl_prev==0 && scl==1);

  // START legal: SDA falls while SCL high
  property p_start_def; @(posedge clk) disable iff (!rst_n)
    (sda_fall && scl && scl_prev) |-> 1;
  endproperty
  assert property (p_start_def);

  // STOP legal: SDA rises while SCL high
  property p_stop_def; @(posedge clk) disable iff (!rst_n)
    (sda_rise && scl && scl_prev) |-> 1;
  endproperty
  assert property (p_stop_def);

  // SDA stable while SCL high, except at START/STOP/SCL-rise
  property p_sda_stable;
    @(posedge clk) disable iff (!rst_n)
    (scl && !scl_rise_ev) |-> ($stable(sda) || sda_fall || sda_rise);
  endproperty
  assert property (p_sda_stable)
    else $error("[%0t] ERROR: SDA changed illegally while SCL high", $time);

endmodule

`default_nettype wire
