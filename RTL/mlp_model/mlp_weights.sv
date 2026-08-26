// Gerado por Scripts/export/gen_mlp_weights_sv.py a partir de mlp_lowband_weights.h.
// NAO editar a mao: rode o gerador de novo depois de retreinar o modelo.
// Classes (indice do argmax): Bearing, Misalign, None, Unbalance
//
// Os pesos NAO ficam mais aqui: foram para RTL/mem/mlp/*.mem, carregados
// por $readmemh em arrays de leitura sincrona (inferencia de M10K).
// Este pacote guarda so as dimensoes e o mapa de enderecos das ROMs.

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
    // ROM layout (see build_roms() in the generator)
    // ---------------------------------------------------------------
    // mlp_weights.mem -- lane-major, one 8-bit weight per line.
    //   lane n holds every weight MAC lane n needs, so all lanes share
    //   one tap offset and differ only by their lane base:
    //     offset 0            .. N_IN-1           : layer 0
    //     offset N_IN         .. N_IN+N_H0-1      : layer 1
    //     offset N_IN+N_H0    .. W_DEPTH-1        : layer 2
    //   lanes >= N_H1 / N_OUT are zero-filled for layers 1 / 2, which is
    //   what retires the old `(n < N_H1) ? ... : '0` select in RTL.
    // The lane count is N_H0 (== N_MAC in mlp.sv); it is not redeclared
    // here so the module's own localparam stays the single definition.
    localparam int W_DEPTH = N_IN + N_H0 + N_H1;   // 132 + 8 + 4 = 144 taps per lane
    localparam int W_WORDS = N_H0 * W_DEPTH;       // 8 * 144 = 1152 words

    // mlp_biases.mem / mlp_scales.mem -- neuron-major, one ACC_WIDTH word
    // per line: layer 0 block, then layer 1, then layer 2.
    localparam int NB_WORDS = N_H0 + N_H1 + N_OUT;  // 8 + 4 + 4 = 16 words

endpackage
