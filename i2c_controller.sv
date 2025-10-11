`timescale 1ns/1ps
`default_nettype none

import cam_i2c_pkg::*;

module i2c_controller #(
    parameter int SYS_CLK    = 100_000_000,
    parameter int I2C_SPEED  = 100_000,
    parameter bit STRETCH_EN = 1
)(
    input  wire logic    clk, rst_n,

    // From sequencer
    input  wire logic       wr_start,       // 1-cycle pulse
    input  wire logic [6:0] wr_dev_addr7,
    input  wire logic [7:0] wr_reg,
    input  wire logic [7:0] wr_val,
    output      logic       wr_busy,
    output      logic       wr_done,        // mirrors master's done
    output      logic       wr_ackerr,      // NACK/timeout flag

    // I2C pins (open-drain)
    inout       tri         sda_io,
    inout       tri         scl_io
);

    // Master connections
    logic          m_busy, m_done, m_nack_addr, m_nack_data, m_timeout;
    logic  [7:0]   m_wr_data;
    logic          m_wr_valid, m_wr_ready;
    logic  [7:0]   m_rd_data;
    logic          m_rd_valid;
    logic          m_start;

    // fixed lengths: write 2 bytes (reg,val), no read
    localparam logic [7:0] WR_LEN = 8'd2;
    localparam logic [7:0] RD_LEN = 8'd0;

    assign wr_busy   = m_busy;
    assign wr_done   = m_done;
    assign wr_ackerr = m_nack_addr | m_nack_data | m_timeout;

    // ------------------------------
    // Feeder FSM:
    //  IDLE -> (wr_start) -> KICK
    //  KICK -> WAIT_REG_RDY (wait for master to request first byte)
    //  WAIT_REG_RDY -> SEND_REG (issue reg when wr_ready)
    //  SEND_REG -> WAIT_VAL_RDY
    //  WAIT_VAL_RDY -> SEND_VAL (issue val when wr_ready)
    //  SEND_VAL -> IDLE (master will complete STOP by itself)
    // ------------------------------
    typedef enum logic [2:0] { 
        W_IDLE, 
        W_KICK, 
        W_WAIT_REG_RDY, 
        W_SEND_REG, 
        W_WAIT_VAL_RDY, 
        W_SEND_VAL 
    } wstate_t;

    wstate_t wstate, wnext;

    // state reg
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) wstate <= W_IDLE;
        else        wstate <= wnext;

    // next-state logic
    always_comb begin
        wnext = wstate;
        unique case (wstate)
            W_IDLE           : if (wr_start && !m_busy)           wnext = W_KICK;

            W_KICK           :                                    wnext = W_WAIT_REG_RDY;

            // Wait until the master enters BYTE_LOAD (wr_ready=1)
            W_WAIT_REG_RDY   : if (m_wr_ready)                    wnext = W_SEND_REG;

            // Assert wr_valid for one clk exactly in the same cycle as wr_ready
            W_SEND_REG       :                                    wnext = W_WAIT_VAL_RDY;

            W_WAIT_VAL_RDY   : if (m_wr_ready)                    wnext = W_SEND_VAL;

            W_SEND_VAL       :                                    wnext = W_IDLE;

            default          :                                    wnext = W_IDLE;
        endcase
    end

    // drive master control + data handshakes (registered)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_start    <= 1'b0;
            m_wr_valid <= 1'b0;
            m_wr_data  <= 8'h00;
        end else begin
            // defaults each cycle
            m_start    <= 1'b0;
            m_wr_valid <= 1'b0;

            unique case (wnext)
                // Launch the I2C transaction (address phase happens inside master)
                W_KICK: begin
                    m_start <= 1'b1;
                end

                // When master is ready for first data byte, send REG for one cycle
                W_SEND_REG: begin
                    // We only ever arrive here from W_WAIT_REG_RDY when m_wr_ready==1
                    m_wr_data  <= wr_reg;
                    m_wr_valid <= 1'b1;   // 1-cycle pulse aligned with wr_ready
                end

                // When master is ready for second data byte, send VAL for one cycle
                W_SEND_VAL: begin
                    // We only ever arrive here from W_WAIT_VAL_RDY when m_wr_ready==1
                    m_wr_data  <= wr_val;
                    m_wr_valid <= 1'b1;   // 1-cycle pulse aligned with wr_ready
                end

                default: begin
                    // keep defaults
                end
            endcase
        end
    end

    // I2C Master instantiation
    i2c_master #(
        .SYS_CLK    (SYS_CLK),
        .I2C_SPEED  (I2C_SPEED),
        .STRETCH_EN (STRETCH_EN)
    ) u_master (
        .clk       (clk),
        .rst_n     (rst_n),

        .start     (m_start),
        .addr7     (wr_dev_addr7),
        .wr_len    (WR_LEN),
        .rd_len    (RD_LEN),

        .busy      (m_busy),
        .done      (m_done),
        .nack_addr (m_nack_addr),
        .nack_data (m_nack_data),
        .timeout   (m_timeout),

        .wr_data   (m_wr_data),
        .wr_valid  (m_wr_valid),
        .wr_ready  (m_wr_ready),

        .rd_data   (m_rd_data),
        .rd_valid  (m_rd_valid),
        .rd_ready  (1'b1),

        .sda_io    (sda_io),
        .scl_io    (scl_io)
    );

endmodule
`default_nettype wire
