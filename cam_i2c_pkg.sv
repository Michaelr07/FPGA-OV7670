package cam_i2c_pkg;

    typedef enum logic [1:0] { OP_WRITE=2'd0, OP_DELAY=2'd1, OP_END=2'd2 } op_t;
    
    typedef struct packed {
    op_t         op;         // OP_WRITE / OP_DELAY / OP_END
    logic [7:0]  reg_addr;   // sensor register (for OP_WRITE)
    logic [7:0]  reg_val;    // value to write   (for OP_WRITE)
    logic [15:0] delay_ms;  // milliseconds     (for OP_DELAY)
  } cmd_t;
  
endpackage