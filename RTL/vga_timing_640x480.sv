import video_pkg::*;

//   Generates VGA timing signals (HSYNC, VSYNC, DE) and current pixel
//   coordinates (X_POS, Y_POS) based on the provided video timing parameters
//   Supports any resolution defined in video_pkg
//
// Parameters:
//   T - Video timing record (default: 640x480@60Hz)
//
// Notes:
//   HSYNC/VSYNC polarity controlled by T.HS_NEG and T.VS_NEG
//   DE asserted during active display region only

module vga_timing
    #(
        parameter video_pkg::vid_timing_t T = video_pkg::TIMING_VGA_640x480 
    )
    (
        input  logic PIX_CLK,
        input  logic RST_N, 
        output logic DE, HSYNC, VSYNC,
        output logic [$clog2(T.H_ACTIVE)-1:0] X_POS,
        output logic [$clog2(T.V_ACTIVE)-1:0] Y_POS
    );
    
    localparam int H_TOTAL = T.H_ACTIVE + T.H_BP + T.H_FP + T.H_SYNC;
    localparam int V_TOTAL = T.V_ACTIVE + T.V_BP + T.V_FP + T.V_SYNC;

    logic [$clog2(H_TOTAL)-1:0] hcnt;
    logic [$clog2(V_TOTAL)-1:0] vcnt;

    logic hs_raw, vs_raw;
    
    always_ff @(posedge PIX_CLK or negedge RST_N) begin
        if (!RST_N) begin
            hcnt <= 0;
            vcnt <= 0;
        end else begin
            if (hcnt == H_TOTAL-1) begin
                hcnt <= '0;
                vcnt <= (vcnt == V_TOTAL-1) ? '0 : vcnt + 1;
            end else begin
                hcnt <= hcnt + 1;
            end
        end
    end

    assign hs_raw = (hcnt >= (T.H_ACTIVE + T.H_FP)) && (hcnt < (T.H_ACTIVE + T.H_FP + T.H_SYNC));
    assign vs_raw = (vcnt >= (T.V_ACTIVE + T.V_FP)) && (vcnt < (T.V_ACTIVE + T.V_FP + T.V_SYNC));

    assign HSYNC = (T.HS_NEG)? ~hs_raw : hs_raw;
    assign VSYNC = (T.VS_NEG)? ~vs_raw : vs_raw;

    assign DE = ((hcnt < T.H_ACTIVE) && (vcnt < T.V_ACTIVE));

    assign X_POS = (hcnt < T.H_ACTIVE)? hcnt[$bits(X_POS)-1:0] : '0;
    assign Y_POS = (vcnt < T.V_ACTIVE)? vcnt[$bits(Y_POS)-1:0] : '0;

endmodule