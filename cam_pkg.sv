package cam_pkg;

typedef struct packed {
    int H_ACTIVE;
    int V_ACTIVE;
    } cam_timing_t;

// VGA
localparam cam_timing_t CAM_VGA_640x480 = '{     
    H_ACTIVE:640, V_ACTIVE:480
};
// QVGA
localparam cam_timing_t CAM_QVGA_320x240 = '{
    H_ACTIVE:320, V_ACTIVE:240
};
// QQVGA
localparam cam_timing_t CAM_QQVGA_160x120 = '{
    H_ACTIVE:160, V_ACTIVE:120
};

endpackage
