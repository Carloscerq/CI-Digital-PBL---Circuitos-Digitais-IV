`timescale 1ns / 1ps

import mlp_weights_pkg::*;

// ============================================================================
// FFT to MLP Feature Collector  (reescrito)
// ============================================================================
// O MAPA DE FEATURES VEIO DO mlp_tb_dpi.sv
// ----------------------------------------
// O testbench do MLP define o contrato de forma inequivoca:
//
//   $display("MODEL %0d inputs (%0d bins + %0d aggregates) ...",
//            N_IN, N_BINS, N_EXTRA);
//
//   features[0 .. N_BINS-1]      -> "|rFFT| bins"
//   features[N_BINS+0]           -> Temperature_housing_A
//   features[N_BINS+1]           -> Temperature_housing_B
//   features[N_BINS+2]           -> U-phase_pow
//   features[N_BINS+3]           -> mdc_k0
//
// Com N_IN = 132 e N_EXTRA = 4, sai N_BINS = 128. Uma FFT de 64 pontos com
// entrada real da 64 saidas, das quais so 32 sao independentes (os bins 32..63
// sao o espelho conjugado dos bins 0..31). Entao:
//
//     4 sensores de vibracao x 32 bins uteis = 128 = N_BINS
//
// A revisao anterior gravava fft_real em [0..63] e fft_imag em [64..127] de UM
// sensor por inferencia. Estava errado em tres frentes ao mesmo tempo: metade
// dos bins era redundante, a parte imaginaria nao e feature nenhuma, e o
// modelo espera os QUATRO sensores no mesmo vetor.
//
// CONSEQUENCIA ARQUITETURAL
// -------------------------
// O collector deixa de ser time-multiplexado (uma inferencia por sensor) e
// passa a juntar uma RODADA COMPLETA dos quatro sensores num unico vetor ->
// uma inferencia a cada quatro frames de FFT. Isso muda o significado de
// `mlp_sensor_id` -- ver MLP_SENSOR_ID_NOTE no fim do arquivo.
// ============================================================================
module fft_to_mlp_collector #(
    parameter int DATA_WIDTH = 24,
    parameter int N_VIB      = 4,    // sensores de vibracao no vetor
    parameter int BINS_USED  = 32,   // bins uteis por sensor (metade de 64)
    parameter int N_AUX      = 3,    // 1 corrente + 2 temperatura

    // Indice em aux_features de cada um dos tres primeiros extras, na ordem
    // que o modelo espera. Com o mapa atual do top_system
    //     aux 0 = current 0     aux 1 = temperature 0     aux 2 = temperature 1
    // e a ordem do TB (TempA, TempB, U-phase_pow):
    parameter int EXTRA_SEL [3] = '{1, 2, 0},

    // 1 = |FFT| aproximado (alpha-max-beta-min); 0 = so a parte real.
    // Ver MAGNITUDE_NOTE no fim do arquivo antes de mudar.
    parameter bit USE_MAGNITUDE = 1
)(
    input  logic clk,
    input  logic reset,                   // SINCRONO, ATIVO EM ALTO

    // Shared-FFT output stream
    input  logic                          fft_valid,
    input  logic                          fft_ready,
    input  logic [5:0]                    fft_bin,
    input  logic signed [DATA_WIDTH-1:0]  fft_real,
    input  logic signed [DATA_WIDTH-1:0]  fft_imag,
    input  logic                          fft_done,
    input  logic [1:0]                    fft_sensor_id,

    // Non-vibration sensors, latest value (raw, ainda sem EXTRA_SHIFT)
    input  logic signed [DATA_WIDTH-1:0]  aux_features [0:N_AUX-1],

    // Quarto agregado do modelo. NAO vem de aux_features -- ver MDC_K0_NOTE.
    input  logic signed [DATA_WIDTH-1:0]  mdc_k0,

    // MLP interface
    output logic signed [ACC_WIDTH-1:0]   mlp_features [N_IN],
    output logic                          mlp_start,
    output logic [1:0]                    mlp_sensor_id,
    input  logic                          mlp_busy,

    output logic                          frame_dropped
);

    localparam int IDX_W = $clog2(N_IN);

    logic signed [ACC_WIDTH-1:0] features_reg [N_IN];
    assign mlp_features = features_reg;

    // ------------------------------------------------------------------
    // Magnitude do bin
    // ------------------------------------------------------------------
    // |z| = sqrt(re^2 + im^2) custa caro. A aproximacao alpha-max-beta-min
    //   |z| ~= max(|re|,|im|) + 0.375 * min(|re|,|im|)
    // erra no maximo ~6.8% e sai em somadores e shifts, sem multiplicador.
    // 0.375 = 1/2 - 1/8, logo (mn>>1) - (mn>>3).
    function automatic logic [DATA_WIDTH-1:0] abs_sat (input logic signed [DATA_WIDTH-1:0] v);
        if (!v[DATA_WIDTH-1])                        return v[DATA_WIDTH-1:0];
        else if (v == {1'b1, {(DATA_WIDTH-1){1'b0}}}) return {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else                                          return (-v);
    endfunction

    logic [DATA_WIDTH-1:0]   abs_re, abs_im, mx, mn;
    logic [DATA_WIDTH+1:0]   mag_full;
    logic signed [ACC_WIDTH-1:0] bin_feature;

    always_comb begin
        abs_re = abs_sat(fft_real);
        abs_im = abs_sat(fft_imag);
        mx     = (abs_re >= abs_im) ? abs_re : abs_im;
        mn     = (abs_re >= abs_im) ? abs_im : abs_re;

        mag_full = {2'b0, mx} + {2'b0, (mn >> 1)} - {2'b0, (mn >> 3)};

        if (USE_MAGNITUDE) begin
            // satura no maximo positivo representavel
            if (mag_full > {2'b0, 1'b0, {(DATA_WIDTH-1){1'b1}}})
                bin_feature = ACC_WIDTH'({1'b0, {(DATA_WIDTH-1){1'b1}}});
            else
                bin_feature = ACC_WIDTH'(mag_full[DATA_WIDTH-1:0]);
        end else begin
            bin_feature = ACC_WIDTH'(fft_real);
        end
    end

    // ------------------------------------------------------------------
    // Extras: shift constante, um assign por slot. Fora do always_ff para
    // que nenhum array de parametro seja indexado por variavel procedural
    // (Quartus Lite transforma isso num cone de mux).
    // ------------------------------------------------------------------
    // EXTRA_SHIFT e negativo para deslocamento a direita, dai a negacao.
    logic signed [ACC_WIDTH-1:0] extra_scaled [N_EXTRA];

    assign extra_scaled[0] = aux_features[EXTRA_SEL[0]] >>> (-EXTRA_SHIFT[0]); // Temp A
    assign extra_scaled[1] = aux_features[EXTRA_SEL[1]] >>> (-EXTRA_SHIFT[1]); // Temp B
    assign extra_scaled[2] = aux_features[EXTRA_SEL[2]] >>> (-EXTRA_SHIFT[2]); // U-phase_pow
    assign extra_scaled[3] = mdc_k0                     >>> (-EXTRA_SHIFT[3]); // mdc_k0

    // ------------------------------------------------------------------
    // Admissao de frame e montagem da rodada
    // ------------------------------------------------------------------.
    logic       fft_xfer;
    logic       frame_start;
    logic       capturing;
    logic       take;
    logic [N_VIB-1:0] round_mask;   // quais sensores ja entraram nesta rodada

    assign fft_xfer    = fft_valid && fft_ready;
    assign frame_start = fft_xfer && (fft_bin == 6'd0);
    assign take        = frame_start ? (!mlp_busy && !mlp_start) : capturing;

    // Endereco do bin dentro do vetor: sensor * BINS_USED + bin
    logic [IDX_W-1:0] bin_addr;
    assign bin_addr = IDX_W'(fft_sensor_id) * IDX_W'(BINS_USED) + IDX_W'(fft_bin);

    logic bin_in_range;
    assign bin_in_range = (fft_bin < 6'(BINS_USED));

    always_ff @(posedge clk) begin
        if (reset) begin
            mlp_start     <= 1'b0;
            capturing     <= 1'b0;
            round_mask    <= '0;
            frame_dropped <= 1'b0;
            for (int i = 0; i < N_IN; i++)
                features_reg[i] <= '0;
        end else begin
            mlp_start <= 1'b0;

            if (frame_start) begin
                capturing <= take;
                if (!take) begin
                    // Rodada incompleta nao serve: descarta o que ja tinha
                    frame_dropped <= 1'b1;
                    round_mask    <= '0;
                end
            end

            // So os bins 0..BINS_USED-1 viram feature; os demais sao o espelho
            // conjugado e nao carregam informacao nova.
            if (fft_xfer && take && bin_in_range)
                features_reg[bin_addr] <= bin_feature;

            if (fft_done) begin
                capturing <= 1'b0;

                if (capturing) begin
                    automatic logic [N_VIB-1:0] next_mask;
                    next_mask = round_mask | (N_VIB'(1) << fft_sensor_id);

                    if (&next_mask) begin
                        // Rodada completa: congela os agregados e dispara
                        for (int e = 0; e < N_EXTRA; e++)
                            features_reg[N_BINS + e] <= extra_scaled[e];
                        mlp_start  <= 1'b1;
                        round_mask <= '0;
                    end else begin
                        round_mask <= next_mask;
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // MLP_SENSOR_ID_NOTE
    // ------------------------------------------------------------------
    assign mlp_sensor_id = 2'd0;

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != ACC_WIDTH)
            $fatal(1, "[fft_to_mlp_collector] DATA_WIDTH != mlp ACC_WIDTH.");
        if (N_BINS != N_VIB * BINS_USED)
            $fatal(1, "[fft_to_mlp_collector] N_BINS (%0d) != N_VIB*BINS_USED (%0d).",
                   N_BINS, N_VIB * BINS_USED);
        if (N_EXTRA != 4)
            $fatal(1, "[fft_to_mlp_collector] N_EXTRA=%0d; o mapa de extras assume 4.",
                   N_EXTRA);
    end
    // synthesis translate_on

endmodule
