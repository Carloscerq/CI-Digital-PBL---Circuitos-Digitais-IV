`timescale 1ns / 1ps

// ============================================================================
// fft_peak_mdc -- detector de picos espectrais + modulo MDC (Euclides)
// ============================================================================

module fft_peak_mdc #(
    parameter int DATA_WIDTH = 24,
    parameter int N_VIB      = 4,    // canais somados; POTENCIA DE 2
    parameter int K_MAX      = 26,   // ultimo bin da busca (MDC_K_MAX)
    parameter int K_MIN      = 2,    // k0 < K_MIN => invalido (MDC_K_MIN)
    parameter int N_PEAKS    = 3,    // fixo em 3: o tracker e desenrolado
    // Limiar relativo. O notebook usa 0,15; aqui vira (mx>>3) + (mx>>5) =
    // 5/32 = 0,15625, que sai so em shifts
    parameter int THR_SH_A   = 3,
    parameter int THR_SH_B   = 5
)(
    input  logic clk,
    input  logic reset,

    // Stream de saida da FFT compartilhada
    input  logic                         fft_valid,
    input  logic                         fft_ready,
    input  logic [5:0]                   fft_bin,
    input  logic signed [DATA_WIDTH-1:0] fft_real,
    input  logic signed [DATA_WIDTH-1:0] fft_imag,
    input  logic [1:0]                   fft_sensor_id,
    input  logic                         fft_done,

    output logic signed [DATA_WIDTH-1:0] mdc_k0,      // ultimo k0 valido (hold)
    output logic                         mdc_valid,   // nivel: rodada atual travou
    output logic                         mdc_update,  // pulso: k0/valid atualizados
    output logic                         mdc_overrun  // sticky: rodada nova cedo demais
);

    // O maximo local em k precisa de mag[k-1] e mag[k+1], logo o acumulador
    // guarda os bins 0 .. K_MAX+1. O bin 0 nunca e candidato a pico (a busca
    // comeca em 1), mas e o vizinho esquerdo de k = 1.
    localparam int ACC_N = K_MAX + 2;
    localparam int ACC_W = DATA_WIDTH + $clog2(N_VIB);   // 24 + 2 = 26
    localparam int K_W   = $clog2(ACC_N);                // 5

    localparam logic [2:0] S_IDLE = 3'd0,   // esperando o fim de uma rodada
                           S_MAX  = 3'd1,   // varredura 1: maior bin da banda
                           S_SCAN = 3'd2,   // varredura 2: maximos locais + top-3
                           S_GCD  = 3'd3,   // Euclides sobre k1, k2, k3
                           S_UPD  = 3'd4;   // valida e segura o resultado

    // ------------------------------------------------------------------
    // Magnitude do bin -- MESMA aproximacao do fft_to_mlp_collector
    // (alpha-max-beta-min, |z| ~= max + 0.375*min = max + (min>>1) - (min>>3)).
    // Duplicada de proposito: o ranking dos picos tem que enxergar exatamente
    // a mesma magnitude que vira feature. Se mudar la, mude aqui tambem.
    // O limiar do MDC e RELATIVO, entao o erro de ~7 % da aproximacao se
    // cancela entre o pico e o maximo da banda.
    // ------------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] abs_sat (input logic signed [DATA_WIDTH-1:0] v);
        if (!v[DATA_WIDTH-1])                         return v[DATA_WIDTH-1:0];
        else if (v == {1'b1, {(DATA_WIDTH-1){1'b0}}}) return {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else                                          return (-v);
    endfunction

    logic [DATA_WIDTH-1:0] abs_re, abs_im, mx_c, mn_c;
    logic [DATA_WIDTH+1:0] mag_full;
    logic [DATA_WIDTH-1:0] bin_mag;

    always_comb begin
        abs_re   = abs_sat(fft_real);
        abs_im   = abs_sat(fft_imag);
        mx_c     = (abs_re >= abs_im) ? abs_re : abs_im;
        mn_c     = (abs_re >= abs_im) ? abs_im : abs_re;
        mag_full = {2'b0, mx_c} + {2'b0, (mn_c >> 1)} - {2'b0, (mn_c >> 3)};
        bin_mag  = (mag_full > {2'b0, 1'b0, {(DATA_WIDTH-1){1'b1}}})
                 ? {1'b0, {(DATA_WIDTH-1){1'b1}}}
                 : mag_full[DATA_WIDTH-1:0];
    end

    // ------------------------------------------------------------------
    // Acumulador por bin: soma das magnitudes dos N_VIB canais.
    // A FFT compartilhada entrega um sensor por vez, em ordem crescente de
    // bin, entao o sensor 0 ESCREVE e os demais SOMAM. Nao precisa de clear.
    // ------------------------------------------------------------------
    logic [ACC_W-1:0] mag_acc [ACC_N];

    logic fft_xfer, acc_in_range, acc_first, round_end;
    assign fft_xfer     = fft_valid && fft_ready;
    assign acc_in_range = fft_xfer && (fft_bin < 6'(ACC_N));
    assign acc_first    = (fft_sensor_id == 2'd0);
    assign round_end    = fft_done && (fft_sensor_id == 2'(N_VIB-1));

    always_ff @(posedge clk) begin
        if (acc_in_range) begin
            if (acc_first)
                mag_acc[fft_bin[K_W-1:0]] <= ACC_W'(bin_mag);
            else
                mag_acc[fft_bin[K_W-1:0]] <= mag_acc[fft_bin[K_W-1:0]] + ACC_W'(bin_mag);
        end
    end

    // ------------------------------------------------------------------
    // Varredura: maximo da banda, depois maximos locais acima do limiar
    // ------------------------------------------------------------------
    logic [2:0]       state;
    logic [K_W-1:0]   k;
    logic [ACC_W-1:0] band_max, thr;
    logic [ACC_W-1:0] pmag1, pmag2, pmag3;
    logic [5:0]       pk1, pk2, pk3;
    logic [1:0]       n_peaks;

    // Tres leituras simultaneas do banco de registradores: k-1, k, k+1.
    // Em S_SCAN k anda de 1 ate K_MAX, logo os indices ficam em 0..K_MAX+1.
    logic [ACC_W-1:0] a_prev, a_cur, a_next;
    assign a_prev = mag_acc[k - K_W'(1)];
    assign a_cur  = mag_acc[k];
    assign a_next = mag_acc[k + K_W'(1)];

    logic is_local_max, is_peak;
    assign is_local_max = (a_cur > a_prev) && (a_cur >= a_next);
    assign is_peak      = is_local_max && (a_cur >= thr);

    // Maximo da banda incluindo o bin corrente: usado no ultimo ciclo de S_MAX
    // para fechar o limiar sem gastar um estado a mais.
    logic [ACC_W-1:0] band_max_next;
    assign band_max_next = (a_cur > band_max) ? a_cur : band_max;

    logic [5:0] gcd_in [3];
    logic [5:0] gcd_out;
    logic [5:0] k0_result;
    logic       gcd_start, gcd_ready, gcd_busy;

    gcd #(.AMOUNT_OF_NUMBERS(3), .SIZE(6)) u_gcd (
        .clk   (clk),
        .reset (reset),
        .start (gcd_start),
        .in    (gcd_in),
        .out   (gcd_out),
        .ready (gcd_ready)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            k           <= K_W'(1);
            band_max    <= '0;
            thr         <= '0;
            pmag1       <= '0;  pmag2 <= '0;  pmag3 <= '0;
            pk1         <= 6'd0; pk2  <= 6'd0; pk3  <= 6'd0;
            n_peaks     <= 2'd0;
            gcd_in[0]   <= 6'd0; gcd_in[1] <= 6'd0; gcd_in[2] <= 6'd0;
            k0_result   <= 6'd0;
            gcd_start   <= 1'b0;
            gcd_busy    <= 1'b0;
            mdc_k0      <= '0;          // "zerado no reset de cada ensaio"
            mdc_valid   <= 1'b0;
            mdc_update  <= 1'b0;
            mdc_overrun <= 1'b0;
        end else begin
            gcd_start  <= 1'b0;
            mdc_update <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                S_IDLE: begin
                    if (round_end) begin
                        band_max <= '0;
                        pmag1    <= '0;  pmag2 <= '0;  pmag3 <= '0;
                        pk1      <= 6'd0; pk2  <= 6'd0; pk3  <= 6'd0;
                        n_peaks  <= 2'd0;
                        k        <= K_W'(1);
                        state    <= S_MAX;
                    end
                end

                // ----------------------------------------------------------
                // mag[1:K_MAX+1].max() do notebook: referencia do limiar.
                S_MAX: begin
                    if (a_cur > band_max) band_max <= a_cur;

                    if (k == K_W'(K_MAX)) begin
                        // 0,15625 = 1/8 + 1/32, so shifts
                        thr   <= (band_max_next >> THR_SH_A)
                               + (band_max_next >> THR_SH_B);
                        k     <= K_W'(1);
                        state <= S_SCAN;
                    end else begin
                        k <= k + K_W'(1);
                    end
                end

                // ----------------------------------------------------------
                // Maximo local acima do limiar, mantendo os 3 maiores.
                // Comparacao estrita (>) => em empate vence o bin de menor
                // indice, o que enviesa para a fundamental e nao para a
                // harmonica.
                S_SCAN: begin
                    if (is_peak) begin
                        if (n_peaks != 2'd3) n_peaks <= n_peaks + 2'd1;

                        if (a_cur > pmag1) begin
                            pmag1 <= a_cur;  pk1 <= {1'b0, k};
                            pmag2 <= pmag1;  pk2 <= pk1;
                            pmag3 <= pmag2;  pk3 <= pk2;
                        end else if (a_cur > pmag2) begin
                            pmag2 <= a_cur;  pk2 <= {1'b0, k};
                            pmag3 <= pmag2;  pk3 <= pk2;
                        end else if (a_cur > pmag3) begin
                            pmag3 <= a_cur;  pk3 <= {1'b0, k};
                        end
                    end

                    if (k == K_W'(K_MAX)) begin
                        state <= S_GCD;
                    end else begin
                        k <= k + K_W'(1);
                    end
                end

                // ----------------------------------------------------------
                // "Menos de MDC_N_PEAKS picos acima do limiar marca o
                //  resultado como invalido" -- nesse caso nem roda Euclides.
                S_GCD: begin
                    if (!gcd_busy && !gcd_start) begin
                        if (n_peaks == 2'd3) begin
                            gcd_in[0] <= pk1;
                            gcd_in[1] <= pk2;
                            gcd_in[2] <= pk3;
                            gcd_start <= 1'b1;
                            gcd_busy  <= 1'b1;
                        end else begin
                            // invalido: segura o ultimo k0, so baixa o valid
                            mdc_valid  <= 1'b0;
                            mdc_update <= 1'b1;
                            state      <= S_IDLE;
                        end
                    end else if (gcd_ready) begin
                        // `out` do gcd so vale no ciclo em que `ready` esta alto
                        gcd_busy  <= 1'b0;
                        k0_result <= gcd_out;
                        state     <= S_UPD;
                    end
                end

                // ----------------------------------------------------------
                // k0 < K_MIN => "MDC(...) = 1 e 'sem harmonicas'", invalido.
                // Valido => registrador com enable segura o novo k0.
                S_UPD: begin
                    if (k0_result >= 6'(K_MIN)) begin
                        mdc_k0    <= DATA_WIDTH'(k0_result);
                        mdc_valid <= 1'b1;
                    end else begin
                        mdc_valid <= 1'b0;
                    end
                    mdc_update <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

            // Uma rodada nova nao pode chegar com a varredura anterior em
            // curso. Com HOP_SIZE = 64 as rodadas ficam a segundos uma da
            // outra e a varredura gasta ~200 ciclos, entao isto e so trava.
            if (round_end && (state != S_IDLE))
                mdc_overrun <= 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (N_PEAKS != 3)
            $fatal(1, "[fft_peak_mdc] N_PEAKS=%0d; o tracker top-3 e desenrolado.", N_PEAKS);
        if (N_VIB != (1 << $clog2(N_VIB)))
            $fatal(1, "[fft_peak_mdc] N_VIB=%0d nao e potencia de 2.", N_VIB);
        if (K_MAX + 1 > 63)
            $fatal(1, "[fft_peak_mdc] K_MAX=%0d nao cabe nos 6 bits de fft_bin.", K_MAX);
        if (K_MIN < 1)
            $fatal(1, "[fft_peak_mdc] K_MIN=%0d invalido.", K_MIN);
    end
    // synthesis translate_on

endmodule
