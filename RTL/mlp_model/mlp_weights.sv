// Gerado por Scripts/export/gen_mlp_weights_sv.py a partir de mlp_lowband_weights.h.
// NAO editar a mao: rode o gerador de novo depois de retreinar o modelo.
// Classes (indice do argmax): Bearing, Misalign, None, Unbalance

package mlp_weights_pkg;

    localparam int W_WIDTH   = 8;   // weight width
    localparam int ACC_WIDTH = 24;  // bias / scale / activation width
    localparam int Q_FRAC    = 15;

    localparam int N_IN  = 132;
    localparam int N_H0  = 8;
    localparam int N_H1  = 4;
    localparam int N_OUT = 4;

    // entradas 0..N_BINS-1  : |rFFT| da banda baixa (Q9.15, ganho 2^9 no W0)
    // entradas N_BINS..N_IN-1: agregados do quadro, cada um deslocado de
    //                          EXTRA_SHIFT bits ANTES de entrar em `features`
    //                          (negativo = deslocamento a direita).
    localparam int N_BINS  = 128;
    localparam int N_EXTRA = 4;
    localparam int EXTRA_SHIFT [4] = '{-6, -6, -5, -6};

    // ---------------------------------------------------------------
    // Layer 0 : 132 -> 8   (ReLU)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L0_W [8][132] = '{
        // neuron 0
        '{   8'sd9,   8'sd17,  -8'sd22,  -8'sd20,   -8'sd8,   8'sd15,   8'sd28,   -8'sd3,
           -8'sd13,   8'sd14,  -8'sd19,    8'sd2,   -8'sd7,  -8'sd22,  -8'sd17,    8'sd5,
           -8'sd28,  -8'sd22,  -8'sd11,  -8'sd35,   -8'sd2,   -8'sd3,  -8'sd24,    8'sd0,
           -8'sd18,  -8'sd10,   -8'sd9,   -8'sd6,   -8'sd2,   -8'sd2,    8'sd3,   -8'sd1,
             8'sd2,    8'sd5,  -8'sd16,  -8'sd37,  -8'sd18,   -8'sd8,   8'sd11,   8'sd15,
           -8'sd10,   8'sd10,  -8'sd39,    8'sd2,  -8'sd30,  -8'sd22,  -8'sd30,   8'sd27,
           -8'sd24,  -8'sd32,  -8'sd18,    8'sd9,  -8'sd19,  -8'sd11,  -8'sd29,   -8'sd2,
             8'sd1,    8'sd3,  -8'sd20,    8'sd4,   -8'sd8,    8'sd5,   8'sd10,  -8'sd12,
            8'sd24,   8'sd27,  -8'sd24,   8'sd30,   8'sd82,    8'sd7,   8'sd51,   8'sd12,
           -8'sd26,   8'sd27,   8'sd14,   -8'sd5,    8'sd6,   8'sd25,  -8'sd18,   -8'sd5,
           -8'sd23,   -8'sd3,  -8'sd10,    8'sd4,    8'sd9,    8'sd8,   8'sd10,   -8'sd8,
           -8'sd17,   8'sd19,   8'sd19,    8'sd0,   -8'sd2,   -8'sd4,    8'sd4,    8'sd9,
            8'sd17,   8'sd28,   -8'sd6,   8'sd38,   8'sd11,   8'sd27,   -8'sd2,    8'sd4,
            8'sd10,   8'sd36,    8'sd3,   -8'sd4,   8'sd26,   8'sd20,  -8'sd21,  -8'sd16,
           -8'sd21,   8'sd14,   8'sd34,   8'sd33,    8'sd3,  -8'sd10,   -8'sd5,   -8'sd3,
           -8'sd25,    8'sd7,   8'sd54,    8'sd3,   -8'sd4,   -8'sd5,  -8'sd19,    8'sd7,
           -8'sd77,  -8'sd60,  -8'sd48,   8'sd60 },
        // neuron 1
        '{  8'sd14,  -8'sd10,   8'sd13,   8'sd15,   -8'sd8,   8'sd32,   8'sd68,    8'sd3,
           -8'sd12,   8'sd21,  -8'sd17,    8'sd9,  -8'sd47,  -8'sd14,  -8'sd38,    8'sd8,
           -8'sd43,  -8'sd31,  -8'sd19,  -8'sd21,  -8'sd17,  -8'sd38,  -8'sd18,   -8'sd2,
            -8'sd3,   -8'sd8,   -8'sd5,   -8'sd8,   -8'sd1,   -8'sd7,   -8'sd4,    8'sd0,
            8'sd15,    8'sd5,   8'sd18,    8'sd5,    8'sd1,   8'sd39,   8'sd10,   -8'sd2,
           -8'sd29,    8'sd6,  -8'sd35,  -8'sd65,  -8'sd22,   8'sd18,  -8'sd18,   8'sd43,
            8'sd25,    8'sd3,    8'sd2,  -8'sd37,  -8'sd37,  -8'sd36,  -8'sd25,   -8'sd1,
            -8'sd5,  -8'sd21,  -8'sd21,    8'sd5,  -8'sd10,   -8'sd4,    8'sd9,    8'sd7,
            8'sd22,   -8'sd1,   8'sd30,   8'sd53,    8'sd5,   8'sd29,  -8'sd34,    8'sd1,
            8'sd47,  -8'sd46,   8'sd13,   8'sd12,   8'sd21,    8'sd9,   8'sd16,   -8'sd9,
             8'sd2,  -8'sd65,  -8'sd22,    8'sd1,   -8'sd6,    8'sd4,  -8'sd33,   -8'sd2,
            -8'sd8,   8'sd20,   8'sd30,   -8'sd8,   -8'sd2,   -8'sd7,    8'sd7,    8'sd2,
            8'sd17,   8'sd17,   8'sd14,    8'sd4,   8'sd31,   8'sd21,   8'sd58,   8'sd11,
            8'sd33,  -8'sd12,    8'sd4,   8'sd20,   8'sd49,  -8'sd27,  -8'sd70,   -8'sd5,
           -8'sd23,   -8'sd1,  -8'sd30,   -8'sd2,  -8'sd17,  -8'sd22,  -8'sd22,   -8'sd3,
            -8'sd9,   8'sd57,   8'sd41,   -8'sd9,   -8'sd3,  -8'sd15,   8'sd29,    8'sd1,
           -8'sd29,  -8'sd24,    8'sd8,   8'sd69 },
        // neuron 2
        '{  -8'sd5,    8'sd6,   8'sd19,    8'sd2,   -8'sd6,    8'sd7,   -8'sd6,   8'sd20,
            8'sd18,   -8'sd9,   -8'sd1,  -8'sd13,   8'sd15,   -8'sd3,   8'sd18,   8'sd28,
           -8'sd14,   8'sd36,   -8'sd2,  -8'sd22,   8'sd14,   -8'sd7,   -8'sd7,   -8'sd1,
             8'sd9,    8'sd0,    8'sd9,    8'sd0,    8'sd0,   -8'sd2,    8'sd0,    8'sd1,
             8'sd2,  -8'sd16,   8'sd13,   8'sd16,    8'sd4,   8'sd29,  -8'sd21,    8'sd3,
           -8'sd24,  -8'sd48,    8'sd6,   -8'sd9,   8'sd17,    8'sd9,    8'sd8,    8'sd0,
             8'sd7,  -8'sd11,   -8'sd9,  -8'sd19,    8'sd4,   8'sd16,   -8'sd8,    8'sd0,
           -8'sd21,  -8'sd27,    8'sd2,   8'sd13,   -8'sd2,    8'sd0,    8'sd3,    8'sd0,
             8'sd4,  -8'sd31,   -8'sd8,  -8'sd22,    8'sd9,    8'sd4,   8'sd21,  -8'sd29,
           -8'sd26,  -8'sd20,   -8'sd6,  -8'sd12,    8'sd3,   -8'sd7,  -8'sd18,    8'sd3,
            -8'sd1,  -8'sd29,  -8'sd16,   8'sd12,   8'sd12,  -8'sd32,   -8'sd4,   -8'sd9,
           -8'sd13,    8'sd1,  -8'sd19,   -8'sd4,   -8'sd1,    8'sd1,   -8'sd6,    8'sd3,
            -8'sd4,   8'sd11,   -8'sd2,   -8'sd3,   8'sd13,    8'sd1,  -8'sd28,  -8'sd43,
            8'sd50,  -8'sd19,    8'sd3,    8'sd2,   -8'sd6,  -8'sd18,   8'sd19,   -8'sd5,
             8'sd1,  -8'sd28,   -8'sd3,    8'sd4,    8'sd4,   -8'sd8,    8'sd6,   -8'sd3,
           -8'sd31,   8'sd37,  -8'sd10,   8'sd11,    8'sd0,    8'sd3,    8'sd2,   -8'sd7,
          -8'sd101,  -8'sd59,   8'sd56,  -8'sd13 },
        // neuron 3
        '{   8'sd2,    8'sd1,   8'sd30,   8'sd28,   8'sd20,   -8'sd9,  -8'sd38,  -8'sd13,
            -8'sd1,  -8'sd39,    8'sd8,   8'sd29,  -8'sd24,    8'sd1,   8'sd28,   8'sd20,
            8'sd38,   8'sd21,   8'sd32,   8'sd23,   8'sd20,  -8'sd10,    8'sd8,   -8'sd2,
            -8'sd2,   -8'sd6,    8'sd5,    8'sd7,    8'sd1,    8'sd1,   -8'sd2,    8'sd5,
            -8'sd2,   8'sd31,   8'sd45,   8'sd23,   8'sd15,   8'sd47,    8'sd6,  -8'sd13,
            8'sd18,   -8'sd8,   8'sd19,   -8'sd5,   8'sd19,   8'sd10,   8'sd23,  -8'sd25,
           -8'sd18,   8'sd11,   8'sd28,  -8'sd24,    8'sd0,  -8'sd28,  -8'sd13,   -8'sd4,
            -8'sd1,    8'sd6,    8'sd6,   8'sd14,    8'sd9,    8'sd5,   -8'sd5,   -8'sd1,
            -8'sd1,    8'sd6,  -8'sd16,   8'sd51,  -8'sd21,  -8'sd13,   8'sd39,    8'sd7,
            8'sd48,    8'sd8,   8'sd17,  -8'sd40,  -8'sd28,   8'sd21,   8'sd35,   8'sd16,
            8'sd55,   8'sd22,   8'sd27,  -8'sd23,    8'sd4,   8'sd14,   -8'sd2,   -8'sd9,
           -8'sd25,  -8'sd26,  -8'sd10,   -8'sd3,    8'sd0,    8'sd3,    8'sd6,   -8'sd3,
            -8'sd1,   8'sd33,   -8'sd2,   8'sd34,   8'sd12,   8'sd32,   8'sd10,   8'sd21,
            8'sd28,   8'sd31,    8'sd4,  -8'sd35,  -8'sd60,   8'sd10,   8'sd93,   8'sd26,
            8'sd40,  -8'sd22,  -8'sd20,    8'sd1,  -8'sd10,   -8'sd6,  -8'sd31,   -8'sd6,
           -8'sd31,  -8'sd67,  -8'sd32,   8'sd22,    8'sd1,   8'sd10,   -8'sd1,   -8'sd9,
            8'sd56,   8'sd56,  -8'sd26,  -8'sd47 },
        // neuron 4
        '{   8'sd0,    8'sd0,    8'sd9,  -8'sd25,  -8'sd10,   8'sd17,   8'sd32,  -8'sd22,
            8'sd17,    8'sd5,  -8'sd12,  -8'sd12,   -8'sd2,  -8'sd18,   8'sd16,  -8'sd14,
           -8'sd11,  -8'sd14,  -8'sd12,    8'sd0,   -8'sd2,  -8'sd19,   -8'sd6,    8'sd0,
           -8'sd23,  -8'sd24,   -8'sd3,   -8'sd2,    8'sd1,   -8'sd3,    8'sd3,    8'sd0,
            -8'sd3,  -8'sd24,    8'sd5,   -8'sd8,    8'sd7,   8'sd26,   8'sd14,    8'sd7,
           -8'sd30,  -8'sd23,  -8'sd14,   8'sd11,  -8'sd33,    8'sd9,   8'sd16,   -8'sd1,
             8'sd6,  -8'sd39,    8'sd2,  -8'sd31,   -8'sd7,    8'sd2,  -8'sd14,   -8'sd2,
           -8'sd17,   -8'sd7,   -8'sd2,    8'sd6,   -8'sd6,    8'sd0,   -8'sd9,    8'sd4,
             8'sd9,  -8'sd29,   8'sd32,   -8'sd2,   8'sd34,   -8'sd6,    8'sd6,   8'sd27,
           -8'sd21,  -8'sd24,  -8'sd15,   8'sd16,   8'sd18,   -8'sd6,   -8'sd1,   -8'sd5,
            8'sd22,  -8'sd24,  -8'sd17,   -8'sd5,   -8'sd2,  -8'sd27,   8'sd15,   -8'sd5,
           -8'sd23,  -8'sd11,   -8'sd3,   -8'sd8,   -8'sd4,    8'sd3,    8'sd0,    8'sd3,
             8'sd8,  -8'sd10,   8'sd11,   8'sd11,   8'sd32,   8'sd10,   8'sd18,   8'sd41,
            8'sd34,    8'sd0,  -8'sd38,   8'sd35,   8'sd56,   -8'sd5,   8'sd19,    8'sd4,
            8'sd39,  -8'sd20,    8'sd1,   -8'sd1,   -8'sd6,  -8'sd36,  -8'sd10,   -8'sd2,
           -8'sd29,   8'sd17,   8'sd16,   -8'sd2,    8'sd0,  -8'sd12,   -8'sd1,   -8'sd1,
           8'sd127,   8'sd80,  -8'sd35,  -8'sd27 },
        // neuron 5
        '{   8'sd5,   8'sd26,   -8'sd4,    8'sd3,   -8'sd7,   8'sd12,   8'sd40,   8'sd19,
           -8'sd41,   8'sd12,  -8'sd11,   8'sd17,  -8'sd35,    8'sd1,   -8'sd1,   8'sd12,
             8'sd9,  -8'sd36,    8'sd6,   -8'sd2,   -8'sd2,  -8'sd30,    8'sd0,    8'sd0,
            -8'sd4,  -8'sd25,   -8'sd7,    8'sd0,   -8'sd1,   -8'sd2,    8'sd3,   -8'sd1,
             8'sd1,  -8'sd18,    8'sd5,  -8'sd33,  -8'sd13,   8'sd23,    8'sd7,  -8'sd26,
           -8'sd13,   8'sd16,  -8'sd38,   8'sd40,  -8'sd29,   -8'sd8,   8'sd52,   8'sd39,
            8'sd57,   -8'sd4,    8'sd7,   -8'sd6,    8'sd1,  -8'sd22,  -8'sd11,    8'sd1,
           -8'sd11,    8'sd8,   -8'sd7,    8'sd7,   -8'sd9,    8'sd2,   -8'sd9,    8'sd4,
           -8'sd11,    8'sd7,    8'sd5,    8'sd0,   -8'sd3,   8'sd14,   8'sd48,  -8'sd34,
             8'sd4,   8'sd10,   8'sd19,   8'sd28,   8'sd16,    8'sd4,   8'sd35,  -8'sd18,
           -8'sd15,    8'sd1,   8'sd26,    8'sd5,   -8'sd7,    8'sd3,    8'sd9,   8'sd14,
            8'sd18,   -8'sd5,   8'sd19,   -8'sd1,    8'sd1,   8'sd10,    8'sd6,    8'sd2,
           -8'sd16,  -8'sd24,  -8'sd24,    8'sd0,  -8'sd18,   8'sd32,   8'sd23,  -8'sd41,
           -8'sd16,   8'sd24,  -8'sd11,   8'sd65,   8'sd12,  -8'sd19,   -8'sd8,  -8'sd19,
            8'sd32,  -8'sd26,    8'sd5,   -8'sd7,  -8'sd22,  -8'sd22,    8'sd5,    8'sd2,
            -8'sd9,  -8'sd53,   8'sd34,   8'sd12,    8'sd1,    8'sd8,   -8'sd5,    8'sd0,
           8'sd114,   8'sd75,  -8'sd21,   8'sd14 },
        // neuron 6
        '{   8'sd7,  -8'sd24,  -8'sd17,   -8'sd6,    8'sd5,    8'sd5,   8'sd24,   8'sd22,
            8'sd13,   8'sd19,   -8'sd8,  -8'sd15,  -8'sd11,  -8'sd24,   -8'sd3,   -8'sd2,
            8'sd12,  -8'sd28,  -8'sd28,   -8'sd8,  -8'sd18,    8'sd6,   -8'sd2,    8'sd0,
            -8'sd6,    8'sd0,  -8'sd12,   -8'sd9,   -8'sd2,   -8'sd5,    8'sd1,    8'sd1,
            -8'sd3,   8'sd10,   -8'sd9,    8'sd1,    8'sd5,   -8'sd8,   8'sd23,   -8'sd6,
             8'sd3,   -8'sd2,  -8'sd34,  -8'sd17,  -8'sd29,  -8'sd12,  -8'sd10,   8'sd43,
             8'sd2,  -8'sd26,  -8'sd21,    8'sd0,  -8'sd17,  -8'sd15,    8'sd5,    8'sd1,
            8'sd18,   -8'sd6,   -8'sd9,   8'sd15,  -8'sd10,   8'sd11,    8'sd3,   -8'sd2,
            8'sd12,    8'sd5,    8'sd4,    8'sd9,   8'sd52,   -8'sd4,  -8'sd19,  -8'sd26,
            -8'sd7,   -8'sd9,    8'sd2,   -8'sd2,   8'sd13,   -8'sd1,   -8'sd2,  -8'sd12,
            8'sd30,   8'sd26,   -8'sd6,  -8'sd16,   -8'sd3,   8'sd18,   8'sd15,    8'sd2,
             8'sd1,   8'sd13,   8'sd10,   -8'sd1,   -8'sd4,    8'sd3,    8'sd1,    8'sd3,
            8'sd17,   8'sd20,    8'sd4,    8'sd7,   8'sd31,  -8'sd16,   8'sd21,  -8'sd25,
            8'sd10,    8'sd2,   -8'sd7,  -8'sd31,   8'sd21,   8'sd33,   8'sd30,  -8'sd13,
            8'sd10,   8'sd27,   8'sd14,    8'sd8,   -8'sd2,    8'sd0,  -8'sd12,    8'sd2,
             8'sd6,   8'sd47,   8'sd31,  -8'sd11,   -8'sd2,    8'sd1,   -8'sd3,    8'sd4,
            8'sd81,   8'sd55,   8'sd98,   8'sd80 },
        // neuron 7
        '{  8'sd17,  -8'sd19,    8'sd1,   8'sd19,   -8'sd4,   -8'sd4,   8'sd22,  -8'sd10,
           -8'sd11,   -8'sd1,  -8'sd26,   -8'sd9,   8'sd11,    8'sd4,   -8'sd7,  -8'sd24,
             8'sd3,   -8'sd3,   -8'sd1,  -8'sd16,  -8'sd12,   -8'sd5,    8'sd3,    8'sd1,
             8'sd5,   -8'sd3,    8'sd2,    8'sd2,   -8'sd1,   -8'sd1,   -8'sd4,   -8'sd2,
            8'sd49,   8'sd34,   8'sd12,   8'sd11,  -8'sd13,  -8'sd35,   8'sd18,   -8'sd9,
            8'sd16,   8'sd24,  -8'sd43,  -8'sd50,   8'sd15,  -8'sd21,  -8'sd10,   -8'sd7,
            8'sd19,  -8'sd17,  -8'sd18,    8'sd5,  -8'sd22,   8'sd18,    8'sd9,    8'sd3,
             8'sd4,   8'sd44,   8'sd10,    8'sd7,    8'sd1,  -8'sd12,   8'sd11,   8'sd11,
            8'sd19,   8'sd46,  -8'sd32,    8'sd3,  -8'sd25,   8'sd62,   8'sd52,    8'sd6,
           -8'sd53,    8'sd6,   8'sd49,   8'sd15,   -8'sd4,   8'sd12,    8'sd3,   -8'sd1,
            8'sd40,  -8'sd18,  -8'sd16,   -8'sd1,   -8'sd4,   8'sd20,   8'sd15,    8'sd6,
            8'sd14,    8'sd1,   8'sd30,   8'sd10,    8'sd0,    8'sd6,    8'sd5,   -8'sd2,
            8'sd14,   8'sd47,   8'sd10,   8'sd28,   -8'sd2,   -8'sd9,   -8'sd8,    8'sd5,
            8'sd38,  -8'sd12,   8'sd15,  -8'sd52,  -8'sd22,   8'sd27,   8'sd20,   -8'sd4,
           -8'sd26,  -8'sd20,   -8'sd5,  -8'sd30,   8'sd10,   8'sd17,   8'sd40,    8'sd4,
            8'sd31,  -8'sd42,    8'sd0,  -8'sd22,   -8'sd1,  -8'sd23,    8'sd1,   8'sd21,
            8'sd50,   8'sd52,   8'sd25,    8'sd9 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L0_B [8] = '{24'sd559692, 24'sd66650, 24'sd772239, -24'sd524336, -24'sd758585, -24'sd884358, -24'sd940082, -24'sd599871};
    // float scale = 0.000600381638  ->  round(scale * 2**30) = 644655   (raw integer input)
    parameter logic signed [ACC_WIDTH-1:0] L0_SCALE [8] = '{24'sd644655, 24'sd644655, 24'sd644655, 24'sd644655, 24'sd644655, 24'sd644655, 24'sd644655, 24'sd644655};

    // ---------------------------------------------------------------
    // Layer 1 : 8 -> 4   (ReLU)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L1_W [4][8] = '{
        // neuron 0
        '{  8'sd18,   8'sd65,   8'sd23,  -8'sd14,  -8'sd31,   8'sd99,   8'sd99,   8'sd40 },
        // neuron 1
        '{ -8'sd37,   -8'sd5,  -8'sd70,   8'sd89,   8'sd96,   8'sd62,   8'sd42,   8'sd74 },
        // neuron 2
        '{ -8'sd33,  -8'sd29,   8'sd32,  8'sd127,    8'sd6,  -8'sd17,    8'sd9,   8'sd11 },
        // neuron 3
        '{  8'sd80,   8'sd81, -8'sd114,  -8'sd43,   8'sd70,  -8'sd77, -8'sd123,   8'sd21 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L1_B [4] = '{-24'sd15034, 24'sd11650, -24'sd5756, 24'sd50913};
    // float scale = 0.0129239075  ->  round(scale * 2**15) = 423   (Q15 input)
    parameter logic signed [ACC_WIDTH-1:0] L1_SCALE [4] = '{24'sd423, 24'sd423, 24'sd423, 24'sd423};

    // ---------------------------------------------------------------
    // Layer 2 : 4 -> 4   (linear -- logits, NO ReLU, argmax outside)
    // ---------------------------------------------------------------
    parameter logic signed [W_WIDTH-1:0] L2_W [4][4] = '{
        // neuron 0
        '{ -8'sd66,   8'sd76,   8'sd45,  -8'sd62 },
        // neuron 1
        '{  8'sd17,   8'sd92,  -8'sd60,  -8'sd66 },
        // neuron 2
        '{ -8'sd54,  -8'sd44,  -8'sd35,   8'sd74 },
        // neuron 3
        '{ 8'sd109, -8'sd127,  -8'sd26, -8'sd104 }
    };
    parameter logic signed [ACC_WIDTH-1:0] L2_B [4] = '{-24'sd20582, -24'sd31195, 24'sd51174, 24'sd23284};
    // float scale = 0.0134428153  ->  round(scale * 2**15) = 440   (Q15 input)
    parameter logic signed [ACC_WIDTH-1:0] L2_SCALE [4] = '{24'sd440, 24'sd440, 24'sd440, 24'sd440};

endpackage
