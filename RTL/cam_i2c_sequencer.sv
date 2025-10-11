// cam_i2c_sequencer.sv
`timescale 1ns/1ps
`default_nettype none
import cam_i2c_pkg::*;

module cam_i2c_sequencer #(
    parameter int unsigned CLK_HZ      = 100_000_000,    // system clock
    parameter bit          USE_TICK    = 1,              // 1: use tick_1ms input; 0: internal ms from CLK_HZ
    parameter logic [6:0]  DEV_ADDR7   = 7'h21,          // OV7670 7-bit write addr (0x42>>1=0x21)
    parameter int unsigned N_CMDS      = 77,             // number of commands in cmds[]
    parameter int unsigned MAX_RETRIES = 2               // I2C write retries on NACK
)(
    input  wire logic clk,
    input  wire logic rst_n,

    // kick the sequence
    input  wire logic start,        // pulse or level; sequencer latches rising edge
    output      logic busy,         // high while running
    output      logic done,         // 1-cycle pulse when complete
    output      logic error,        // latched if any write fails after retries

    // optional external 1ms tick
    input  wire logic tick_1ms,     // valid if USE_TICK=1
 
    // command ROM (static from a higher level)
    input  wire cam_i2c_pkg::cmd_t cmds [N_CMDS],
    output      logic       init_done,
    // Byte-writer interface
    output      logic       wr_start,
    output      logic [6:0] wr_dev_addr7,
    output      logic [7:0] wr_reg,
    output      logic [7:0] wr_val,
    input  wire logic       wr_busy,
    input  wire logic       wr_done,
    input  wire logic       wr_ackerr
);
    typedef enum logic [2:0] {
        S_IDLE, S_FETCH, S_WRITE_LAUNCH, S_WRITE_WAIT,
        S_DELAY, S_NEXT, S_DONE, S_FAIL
    } state_type;
    
    state_type state, next;
  
    //1ms tick
    logic tick_ms_int, tick;
    
    generate                       
        if (USE_TICK) begin
            assign tick_ms_int = 1'b0;          // unused
            assign tick        = tick_1ms;
        end else begin : gen_ms
            localparam int MS_DIV = (CLK_HZ+999)/1000;
            n_counter #(.DIV(MS_DIV)) clk_pulse (
                .clk(clk), .rst_n(rst_n), .en(state == S_DELAY), .done(tick_ms_int)
            );
            assign tick = tick_ms_int;
        end
    endgenerate
    
    cmd_t cur;                                  // current command
    
    localparam int RETW = (MAX_RETRIES <= 1)? 1 : $clog2(MAX_RETRIES+1);
    localparam int IDXW = (N_CMDS <=  1)    ? 1 : $clog2(N_CMDS);
    
    logic [15:0] delay_left;
    logic [RETW-1:0] retries;                   // number of retries
    logic [IDXW-1:0] idx;                       // index of cmd
    
    assign wr_dev_addr7 = DEV_ADDR7;            //assigning slave addr
    
    always_comb begin         
        cur = cmds[idx];                        // Comb read from ROM in a struct variable
    end
    
    // FSM
    
    // state register
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)     state    <= S_IDLE;
        else            state    <= next;
            
    always_comb begin
        next = state;
        case(state)
            S_IDLE          : if (start)            next = S_FETCH;     // check for start pulse then go to fetch
            S_FETCH         : case (cur.op)
                                    OP_WRITE :      next = S_WRITE_LAUNCH;
                                    OP_DELAY :      next = (cur.delay_ms == 0)? S_NEXT : S_DELAY;
                                    OP_END   :      next = S_DONE;
                                    default  :      next = S_FAIL;
                                endcase
            S_WRITE_LAUNCH  :                       next = S_WRITE_WAIT;
            S_WRITE_WAIT    : if (wr_done)
                                    if(wr_ackerr)   next = (retries < MAX_RETRIES)? S_WRITE_LAUNCH : S_FAIL;
                                    else            next = S_NEXT;
            S_DELAY         :                       next = (delay_left == 0)?  S_NEXT : S_DELAY;
            S_NEXT          :                       next = (idx == N_CMDS-1)?  S_DONE : S_FETCH;
            S_DONE          : if (!start)           next = S_IDLE; 
            S_FAIL          : ;                                         // stay until reset
            default         : ;
        endcase
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            delay_left              <= '0;
            retries                 <= '0;
            {busy, done, error}     <= '0;
            wr_start                <= '0;
            wr_reg                  <= '0;
            wr_val                  <= '0;
            idx                     <= '0;
        end
        else begin
            wr_start    <= 1'b0;
            busy        <= 1'b1;
            case(next)
                S_IDLE          : begin                            
                                    idx         <= '0;
                                    retries     <= '0;
                                    delay_left  <= 1'b0;
                                    busy        <= 1'b0;
                                    if (start) 
                                        error       <= 1'b0;
                                  end
                S_FETCH         : begin
                                    retries     <= '0;
                                    wr_reg      <= cur.reg_addr;
                                    wr_val      <= cur.reg_val;
                                    if (cur.op == OP_DELAY) 
                                        delay_left  <= cur.delay_ms; // preloading delay value
                                  end 
                S_WRITE_LAUNCH  : begin
                                    if (!wr_busy)
                                        wr_start    <= 1'b1;
                                  end   
                S_WRITE_WAIT    : begin
                                    if (wr_done && wr_ackerr)
                                        if (retries < MAX_RETRIES) 
                                            retries <= retries + 1;
                                        else                        
                                            error   <= 1'b1;
                                  end 
                S_DELAY         : begin
                                    if(tick && (delay_left != 0)) 
                                        delay_left  <= delay_left - 1;                                    
                                  end 
                S_NEXT          : begin   
                                    if (idx != N_CMDS-1)
                                        idx <= idx + 1;
                                  end   
                S_DONE          : begin
                                    done    <= 1'b1;
                                    busy    <= 1'b0;
                                  end     // we assert done
                S_FAIL          : begin
                                    busy    <= 1'b0;
                                  end      
                default         : ;
            endcase
        end
    end
    
endmodule

`default_nettype wire