package mlp_weights_pkg;

    localparam int W_WIDTH   = 8;   // weight width
    localparam int ACC_WIDTH = 24;  // bias / scale / activation width
    localparam int Q_FRAC    = 15;

    localparam int N_IN  = 40;
    localparam int N_H0  = 8;
    localparam int N_H1  = 4;
    localparam int N_OUT = 4;

    // ---------------------------------------------------------------
    // Layer 0 : 40 -> 8   (ReLU)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L0_W [8][40] = '{
        // neuron 0
        '{  8'sd18,  8'sd18,  -8'sd2, -8'sd32,   8'sd7,  -8'sd9,  8'sd10,  8'sd14,
              8'sd4, -8'sd121, -8'sd36,  -8'sd5,   8'sd4,  -8'sd8,  8'sd12, -8'sd16,
              8'sd6,   8'sd3,   8'sd8, -8'sd29,  8'sd18,  8'sd12, -8'sd44,  -8'sd5,
             8'sd16,   8'sd4, -8'sd15,  8'sd19, -8'sd24, -8'sd69,  8'sd60,  8'sd10,
            -8'sd18, -8'sd20, 8'sd127,  8'sd18, -8'sd14,  8'sd25,  8'sd66,  8'sd78 },
        // neuron 1
        '{   8'sd1,  -8'sd4,   8'sd6,  -8'sd2,  8'sd27, -8'sd13,  8'sd21,  8'sd35,
             8'sd10, -8'sd30, -8'sd10,  8'sd28,   8'sd7,   8'sd7,  8'sd13,  -8'sd8,
            -8'sd20,  -8'sd8,  8'sd12,  -8'sd9,   8'sd5,   8'sd0,   8'sd6,  -8'sd9,
             8'sd29,  -8'sd6,   8'sd4,   8'sd5,  8'sd36,  -8'sd3,  8'sd10,  -8'sd2,
             8'sd47,  -8'sd5,   8'sd7,   8'sd7,   8'sd9,   8'sd5,   8'sd2, -8'sd16 },
        // neuron 2
        '{  8'sd42,  8'sd62,  -8'sd5,   8'sd1,   8'sd4,  -8'sd4,  8'sd24,  8'sd40,
             8'sd46,  -8'sd8, -8'sd49, -8'sd24,  8'sd40,  -8'sd8,   8'sd4,  8'sd32,
              8'sd5,  8'sd40,  -8'sd3, -8'sd33,  8'sd12,   8'sd9, -8'sd45, -8'sd14,
            -8'sd20,  8'sd21, -8'sd29,  8'sd32,  8'sd24, -8'sd39, -8'sd58,  8'sd14,
             8'sd73, -8'sd18,   8'sd3,  8'sd21, -8'sd31,  8'sd44,  8'sd36, -8'sd15 },
        // neuron 3
        '{ -8'sd16,  -8'sd1,  8'sd14,   8'sd6, -8'sd30,   8'sd3, -8'sd22, -8'sd49,
            -8'sd16,  8'sd38,  8'sd15,   8'sd2,   8'sd9,   8'sd2,   8'sd7,   8'sd7,
             8'sd23,   8'sd6,   8'sd8,  8'sd13, -8'sd61,  -8'sd5,  8'sd15, -8'sd11,
            -8'sd44,   8'sd1, -8'sd13,  -8'sd6, -8'sd50, -8'sd37, -8'sd67,  -8'sd9,
            -8'sd34, -8'sd40,  -8'sd4, -8'sd70, -8'sd13, -8'sd38, -8'sd15, -8'sd21 },
        // neuron 4
        '{  -8'sd3,   8'sd9,   8'sd6, -8'sd11,  -8'sd2, -8'sd19,   8'sd9,  8'sd49,
             8'sd74, -8'sd12, -8'sd13,  -8'sd6, -8'sd24, -8'sd27,  -8'sd1,  -8'sd7,
              8'sd0,  8'sd33,  8'sd43,  -8'sd6,  -8'sd1,  -8'sd7,  8'sd10,  -8'sd9,
              8'sd3, -8'sd10,  -8'sd2,  8'sd22, -8'sd12, -8'sd17, -8'sd48,  8'sd19,
            -8'sd75, -8'sd59,   8'sd4, -8'sd57, -8'sd22,   8'sd1,   8'sd4,  -8'sd1 },
        // neuron 5
        '{  8'sd12,  -8'sd1,   8'sd2,  -8'sd3,  -8'sd9,  8'sd11,  8'sd14,  8'sd10,
            -8'sd19, -8'sd37,  8'sd45,  8'sd15,  -8'sd1,  8'sd20, -8'sd15,  8'sd16,
              8'sd6,  8'sd16,  8'sd22, -8'sd28,  8'sd19,   8'sd9,   8'sd7,  8'sd21,
            -8'sd35, -8'sd12,   8'sd1,   8'sd8, -8'sd10, -8'sd12,   8'sd1,  -8'sd4,
             8'sd37,  8'sd11,   8'sd9,   8'sd0,   8'sd8,  -8'sd8, -8'sd10, -8'sd40 },
        // neuron 6
        '{ -8'sd10, -8'sd21, -8'sd24,  -8'sd2,  8'sd11,  -8'sd1, -8'sd18,  8'sd22,
             8'sd35, -8'sd26, -8'sd27, -8'sd35, -8'sd22, -8'sd14, -8'sd17,  -8'sd2,
             8'sd76,  8'sd38,   8'sd1, -8'sd39, -8'sd18,  8'sd10, -8'sd30,   8'sd7,
            -8'sd19,  8'sd29, -8'sd14,  8'sd15,   8'sd6, -8'sd53, -8'sd66, 8'sd119,
            -8'sd61,  8'sd11, -8'sd103,  8'sd18,  -8'sd3,  8'sd21,  8'sd60,  8'sd58 },
        // neuron 7
        '{  8'sd29, -8'sd10,  8'sd18,  8'sd13,   8'sd5, -8'sd10,   8'sd6,  8'sd29,
             8'sd35, -8'sd95, -8'sd36, -8'sd21, -8'sd11,  -8'sd6, -8'sd26, -8'sd34,
             8'sd23,  8'sd33,   8'sd7, -8'sd44, -8'sd29,  -8'sd7,  8'sd22, -8'sd16,
            -8'sd26,  -8'sd7, -8'sd59, -8'sd28,  8'sd19, -8'sd82,  -8'sd9,  8'sd11,
            -8'sd26,  8'sd34,  8'sd18,  -8'sd2, -8'sd43,  -8'sd4, -8'sd24, -8'sd114 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L0_B [8] = '{24'sd19652, -24'sd39153, -24'sd28372, 24'sd66263, 24'sd21176, 24'sd9374, 24'sd85442, 24'sd129602};
    // float scale = 8.21954681e-07  ->  round(scale * 2**30) = 883   (raw integer input)
    parameter logic signed [ACC_WIDTH-1:0] L0_SCALE [8] = '{24'sd883, 24'sd883, 24'sd883, 24'sd883, 24'sd883, 24'sd883, 24'sd883, 24'sd883};

    // ---------------------------------------------------------------
    // Layer 1 : 8 -> 4    (ReLU)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L1_W [4][8] = '{
        // neuron 0
        '{   8'sd0,   8'sd0,   8'sd0,   8'sd0,   8'sd0,   8'sd0,   8'sd0,   8'sd0 },
        // neuron 1
        '{  -8'sd1, 8'sd118, 8'sd124, -8'sd33, -8'sd46,  8'sd41,  -8'sd3, -8'sd19 },
        // neuron 2
        '{ -8'sd18, -8'sd16,  8'sd17, -8'sd83, 8'sd106,  8'sd81,  8'sd39,   8'sd1 },
        // neuron 3
        '{  8'sd46,  8'sd67, -8'sd127,  8'sd48,  8'sd18,   8'sd5,  8'sd49,  8'sd78 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L1_B [4] = '{-24'sd17539, 24'sd34577, 24'sd12385, 24'sd3823};
    // float scale = 0.0200690366  ->  round(scale * 2**15) = 658   (Q15 input)
    parameter logic signed [ACC_WIDTH-1:0] L1_SCALE [4] = '{24'sd658, 24'sd658, 24'sd658, 24'sd658};

    // ---------------------------------------------------------------
    // Layer 2 : 4 -> 4    (linear -- logits, NO ReLU, argmax outside)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L2_W [4][4] = '{
        // neuron 0
        '{   8'sd0,  8'sd51,   8'sd6, -8'sd31 },
        // neuron 1
        '{   8'sd0, -8'sd20,  8'sd38,   8'sd6 },
        // neuron 2
        '{   8'sd0, -8'sd127, -8'sd43,   8'sd9 },
        // neuron 3
        '{   8'sd0,   8'sd6, -8'sd51,  8'sd23 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L2_B [4] = '{-24'sd38583, -24'sd36307, 24'sd70032, 24'sd1955};
    // float scale = 0.0462269932  ->  round(scale * 2**15) = 1515   (Q15 input)
    parameter logic signed [ACC_WIDTH-1:0] L2_SCALE [4] = '{24'sd1515, 24'sd1515, 24'sd1515, 24'sd1515};

endpackage