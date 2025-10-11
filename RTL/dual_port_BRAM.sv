`timescale 1ns / 1ps

module dual_port_BRAM #(
    parameter int   DATA_BITS = 12,
    parameter int   ADDR_W = 480*640
)(
    input wire logic                    wclk, rclk,
    input wire logic [$clog2(ADDR_W)-1:0]       waddr, raddr,
    input wire logic                    wr, rd,
    input wire logic                    en,
    input wire logic [DATA_BITS-1:0]    wdata,
    output     logic [DATA_BITS-1:0]    rdata
);

    (* ram_style = "block" *) logic [DATA_BITS-1:0] myram [0:ADDR_W-1];
    
    always_ff @(posedge wclk)
        if (en)
            if(wr)
                myram[waddr] <= wdata;  
    
    always_ff @(posedge rclk)
        if (rd)
            rdata   <= myram[raddr];

endmodule
