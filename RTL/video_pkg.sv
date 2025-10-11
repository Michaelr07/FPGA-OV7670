package video_pkg;

  localparam int RGBW = 4; //bits per channel
    
  typedef struct packed {
    int H_ACTIVE, H_FP, H_SYNC, H_BP;
    int V_ACTIVE, V_FP, V_SYNC, V_BP;
    bit HS_NEG; // 1 = active low
    bit VS_NEG;
  } vid_timing_t;

  // 640x480@60 (25.175 MHz nominal)
  localparam vid_timing_t TIMING_VGA_640x480 = '{
    H_ACTIVE:640, H_FP:16,  H_SYNC:96,  H_BP:48,
    V_ACTIVE:480, V_FP:10,  V_SYNC:2,   V_BP:33,
    HS_NEG:1, VS_NEG:1
  };

  // 720p60 (74.25 MHz)
  localparam vid_timing_t TIMING_720P_60 = '{
    H_ACTIVE:1280, H_FP:110, H_SYNC:40,  H_BP:220,
    V_ACTIVE:720,  V_FP:5,   V_SYNC:5,   V_BP:20,
    HS_NEG:1, VS_NEG:1
  };

  // 1080p30 (74.25 MHz) — nice stepping stone
  localparam vid_timing_t TIMING_1080P_30 = '{
    H_ACTIVE:1920, H_FP:88,  H_SYNC:44,  H_BP:148,
    V_ACTIVE:1080, V_FP:4,   V_SYNC:5,   V_BP:36,
    HS_NEG:1, VS_NEG:1
  };
  
  typedef struct packed {
    logic       de;     // data enable
    logic       sof;    // start of frame
    logic       eol;    // end of line
    logic [9:0] x;      // pixel x position
    logic [9:0] y;      // pixel y position
  } vid_sideband_t;
  
  
  typedef struct packed {
   logic [RGBW-1:0] R;
   logic [RGBW-1:0] G;
   logic [RGBW-1:0] B;
   //logic DE;
  } pixel_t;
  
  typedef struct packed {
    pixel_t         px;
    vid_sideband_t  sb;
  } video_word_t;
  
endpackage
