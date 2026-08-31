`timescale 1ns / 1ps

import mlp_weights_pkg::*;   // N_IN, N_BINS, N_EXTRA, ACC_WIDTH

// ============================================================================
// Top Level System
// ============================================================================
module top_system #(
    parameter int DATA_WIDTH  = 24,

    // Parametros do enlace UART
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic clk,
    input  logic reset,                 // Reset SINCRONO, ATIVO EM ALTO

    // UART receive pin -- every sensor value arrives here
    input  logic uart_rx,

    // Decision outputs
    output logic [2:0] status_leds,     // [2]=Critical, [1]=Warning, [0]=Normal
    output logic [3:0] sensor_fault_mask,
    output logic       alert_flag,
    output logic       sys_error        // sticky: framing / overrun / desync
);

    localparam CONV2_WEIGHTS_FILE = "../mem/cnn/conv2d_weights.mem";
    localparam CONV2_BIASES_FILE  = "../mem/cnn/conv2d_biases.mem";
    localparam DENSE_WEIGHTS_FILE = "../mem/cnn/dense_weights.mem";
    localparam DENSE_BIASES_FILE  = "../mem/cnn/dense_biases.mem";

    // ------------------------------------------------------------------------
    // Sensor map. Word order inside one UART frame.
    // ------------------------------------------------------------------------
    localparam int N_VIB     = 4;   // vibration    -> FFT
    localparam int N_CUR     = 1;   // current      -> MLP extras
    localparam int N_TMP     = 2;   // temperature  -> MLP extras
    localparam int N_SENSORS = N_VIB + N_CUR + N_TMP;   // 7
    localparam int N_AUX     = N_CUR + N_TMP;           // 3

    localparam int SPEC_BINS   = 32;  // bins per spectrogram row  (CNN width)
    localparam int SPEC_FRAMES = 32;  // rows per spectrogram      (CNN height)

    localparam int BYTES_PER_WORD = DATA_WIDTH/8;                     // 3
    localparam int FRAME_BYTES    = 2 + N_SENSORS*BYTES_PER_WORD + 1; // 24

    // ------------------------------------------------------------------------
    // UART Data Ingestion
    // ------------------------------------------------------------------------
    logic [2:0] uart_rx_sync;
    always_ff @(posedge clk) begin
        if (reset) uart_rx_sync <= 3'b111;
        else       uart_rx_sync <= {uart_rx_sync[1:0], uart_rx};
    end

    logic [7:0] uart_rx_data;
    logic       uart_rx_ready;
    logic       uart_rx_ready_clr;
    logic       uart_rx_clk_en;
    logic       uart_tx_clk_en_unused;

    baudrate #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (16)
    ) u_uart_baud (
        .clk      (clk),
        .rst      (reset),
        .rx_clk_en(uart_rx_clk_en),
        .tx_clk_en(uart_tx_clk_en_unused)
    );

    receiver #(
        .OVERSAMPLE(16)
    ) u_uart_rx (
        .clk      (clk),
        .rst      (reset),
        .clk_en   (uart_rx_clk_en),
        .rx       (uart_rx_sync[2]),
        .rx_en    (1'b0),           // rx_en e ATIVO EM BAIXO: 0 = habilitado
        .ready_clr(uart_rx_ready_clr),
        .ready    (uart_rx_ready),
        .data     (uart_rx_data)
    );

    logic signed [DATA_WIDTH-1:0] sensor_data [0:N_SENSORS-1];
    logic sensor_frame_valid;
    logic sensor_frame_error;

    uart_sensor_frame_rx #(
        .DATA_WIDTH        (DATA_WIDTH),
        .N_SENSORS         (N_SENSORS),
        .BYTES_PER_WORD    (BYTES_PER_WORD),
        .CLK_FREQ_HZ       (CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .IDLE_TIMEOUT_BYTES(4)
    ) u_frame_rx (
        .clk         (clk),
        .reset       (reset),
        .rx_data     (uart_rx_data),
        .rx_ready    (uart_rx_ready),
        .rx_ready_clr(uart_rx_ready_clr),
        .sensor_data (sensor_data),
        .frame_valid (sensor_frame_valid),
        .frame_error (sensor_frame_error)
    );

    // ------------------------------------------------------------------------
    // Non-vibration sensors -> MLP extras
    // ------------------------------------------------------------------------
    // MUDOU com N_CUR 3 -> 1: os indices de aux_features agora sao
    //   0 = current 0        1..2 = temperature 0..1
    // (antes eram 0..2 = current, 3..4 = temperature).
    //
    // EXTRA_SEL resolvido pelo mlp_tb_dpi: o modelo espera os agregados na
    // ordem (Temperature_housing_A, Temperature_housing_B, U-phase_pow), logo
    // EXTRA_SEL = '{1, 2, 0} com o mapa acima. O quarto agregado (mdc_k0) nao
    // sai daqui -- ver MDC_K0_NOTE no bloco do MLP.
    logic signed [DATA_WIDTH-1:0] aux_features [0:N_AUX-1];
    genvar a;
    generate
        for (a = 0; a < N_AUX; a++) begin : g_aux
            assign aux_features[a] = sensor_data[N_VIB + a];
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Vibration quad -> shared FFT handshake
    // ------------------------------------------------------------------------
    // UART cannot be back-pressured, so the four vibration samples are held in
    // a one-deep register until the pipeline accepts them atomically. The FIR
    // front-end is decimate-by-32, so it drains far faster than UART fills;
    // `vib_overrun` latches if that ever stops holding.
    logic signed [DATA_WIDTH-1:0] vib_hold [0:N_VIB-1];
    logic vib_valid;
    logic vib_ready;
    logic vib_overrun;

    always_ff @(posedge clk) begin
        if (reset) begin
            vib_valid   <= 1'b0;
            vib_overrun <= 1'b0;
            for (int i = 0; i < N_VIB; i++) vib_hold[i] <= '0;
        end else begin
            if (vib_valid && vib_ready)
                vib_valid <= 1'b0;

            if (sensor_frame_valid) begin
                if (vib_valid && !vib_ready)
                    vib_overrun <= 1'b1;         // previous sample not taken yet
                for (int i = 0; i < N_VIB; i++) vib_hold[i] <= sensor_data[i];
                vib_valid <= 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Signal Processing: four channels, one shared 64-point FFT
    // ------------------------------------------------------------------------
    logic fft_valid;
    logic fft_ready;
    logic [5:0] fft_bin;
    logic signed [DATA_WIDTH-1:0] fft_real;
    logic signed [DATA_WIDTH-1:0] fft_imag;
    logic [1:0] fft_sensor_id;
    logic fft_done;

    // The coefficient paths are resolved by Quartus relative to the project
    // directory (RTL/quartus/); the module defaults assume the FFT's own
    // project, so they are overridden here.
    preprocess_fft_shared_4sensor_q915_no_lms #(
        .DATA_WIDTH(DATA_WIDTH),
        .NORMALIZE(1),
        .HOP_SIZE(64),
        .FIR_STAGE1_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage1_decim4_q117.bin"),
        .FIR_STAGE2_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage2_decim4_q117.bin"),
        .FIR_STAGE3_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage3_decim2_q117.bin"),
        .HANN_FILE      ("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/windowing/hann_64_q117.bin")
    ) u_fft_pipeline (
        .clk(clk),
        .reset(reset),

        .sensor1_sample(vib_hold[0]),
        .sensor2_sample(vib_hold[1]),
        .sensor3_sample(vib_hold[2]),
        .sensor4_sample(vib_hold[3]),
        .sample_valid(vib_valid),
        .sample_ready(vib_ready),

        .fft_valid(fft_valid),
        .fft_ready(fft_ready),
        .fft_bin(fft_bin),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_sensor_id(fft_sensor_id),
        .fft_done(fft_done),
        .pipeline_busy(),

        // Debug and event flags left unconnected for brevity
        .decimated_events(),
        .fir_stage1_saturation_events(),
        .fir_stage2_saturation_events(),
        .fir_stage3_saturation_events(),
        .hann_saturation_event(),
        .hann_saturation_sensor_id(),
        .fft_overflow_event(),
        .fft_overflow_stage(),
        .fft_overflow_components(),
        .fft_overflow_sensor_id()
    );

    // ------------------------------------------------------------------------
    // Path A: MLP -- uma inferencia por RODADA dos quatro sensores
    // ------------------------------------------------------------------------
    // O mapa de features saiu do mlp_tb_dpi.sv:
    //   features[0   .. 127] = |FFT| dos 32 bins uteis x 4 sensores
    //   features[128]        = Temperature_housing_A
    //   features[129]        = Temperature_housing_B
    //   features[130]        = U-phase_pow
    //   features[131]        = mdc_k0
    //
    // >>> MDC_K0_NOTE <<<
    // O quarto agregado nao vem de nenhum dos sensores auxiliares -- e um
    // agregado do proprio frame (faixa 0..64 no TB; pelo nome, a componente
    // DC / media do bloco). O pipeline de FFT tem um estagio de remocao de
    // media, mas NAO exporta esse valor na lista de portas, entao nao tenho de
    // onde puxa-lo. Fica amarrado em zero ate a fonte existir; enquanto isso a
    // quarta feature agregada vai constante para o modelo.
    logic signed [DATA_WIDTH-1:0] mdc_k0;
    assign mdc_k0 = '0;   // TODO: ligar na saida de media/DC do front-end da FFT

    logic signed [ACC_WIDTH-1:0] mlp_features [N_IN];
    logic mlp_start;
    logic [1:0] mlp_sensor_id;
    logic mlp_busy_internal;
    logic mlp_frame_dropped;

    fft_to_mlp_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_VIB     (N_VIB),
        .BINS_USED (SPEC_BINS),      // 32 bins uteis por sensor
        .N_AUX     (N_AUX),
        // aux 0 = current, 1 = temp A, 2 = temp B; a ordem do modelo e
        // (TempA, TempB, U-phase_pow) -> '{1, 2, 0}
        .EXTRA_SEL ('{1, 2, 0}),
        .USE_MAGNITUDE(1)            // ver MAGNITUDE_NOTE no collector
    ) u_feature_collector (
        .clk(clk),
        .reset(reset),
        .fft_valid(fft_valid),
        .fft_ready(fft_ready),
        .fft_bin(fft_bin),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_done(fft_done),
        .fft_sensor_id(fft_sensor_id),
        .aux_features(aux_features),
        .mdc_k0(mdc_k0),
        .mlp_features(mlp_features),
        .mlp_start(mlp_start),
        .mlp_sensor_id(mlp_sensor_id),
        .mlp_busy(mlp_busy_internal),
        .frame_dropped(mlp_frame_dropped)
    );

    logic signed [ACC_WIDTH-1:0] mlp_logits [N_OUT];
    logic [1:0] mlp_class_idx;
    logic mlp_done;

    mlp u_mlp (
        .clk(clk),
        .reset(reset),        // ver RESET_CONVERSION_NOTE (era rst_n)
        .start(mlp_start),
        .features(mlp_features),
        .logits(mlp_logits),
        .class_idx(mlp_class_idx),
        .busy(mlp_busy_internal),
        .done(mlp_done)
    );

    // >>> SENSOR_FAULT_MASK_NOTE <<<
    // Este registrador existia para atribuir o resultado do MLP ao sensor que
    // estava sendo coletado. Com o modelo olhando os QUATRO sensores no mesmo
    // vetor, essa atribuicao nao existe mais: a saida e uma classe para a
    // maquina inteira. mlp_sensor_id vem zerado do collector, entao este
    // registrador fica constante em 0 e o inference_arbiter perde a
    // informacao por-sensor vinda do MLP.
    //
    // O arbiter precisa ser revisto: ou sensor_fault_mask passa a vir so do
    // caminho da CNN, ou vira um flag global, ou se treina um modelo por
    // sensor. Nao decidi por voce -- mantive o caminho ligado para nao quebrar
    // a interface.
    logic [1:0] mlp_result_sensor_id;
    always_ff @(posedge clk) begin
        if (reset)          mlp_result_sensor_id <= 2'd0;
        else if (mlp_start) mlp_result_sensor_id <= mlp_sensor_id;
    end

    // ------------------------------------------------------------------------
    // Path B: four spectrograms -> the CNN's four input channels
    // ------------------------------------------------------------------------
    logic [N_VIB-1:0] spec_s_valid;
    logic [N_VIB-1:0] spec_s_ready;
    logic signed [DATA_WIDTH-1:0] spec_s_data [0:N_VIB-1];
    logic [N_VIB-1:0] spec_s_last;

    logic [N_VIB-1:0] spec_m_valid;
    logic [N_VIB-1:0] spec_m_ready;
    logic signed [DATA_WIDTH-1:0] spec_m_data [0:N_VIB-1];
    logic [N_VIB-1:0] spec_m_last;

    genvar s;
    generate
        for (s = 0; s < N_VIB; s++) begin : g_spec
            fft_to_stream_adapter #(
                .DATA_WIDTH(DATA_WIDTH),
                .BINS_PER_FRAME(SPEC_BINS),
                .FRAMES_PER_SPECTROGRAM(SPEC_FRAMES),
                .SENSOR_ID(s)
            ) u_fft_to_spec_adapter (
                .clk(clk),
                .reset(reset),
                .fft_valid(fft_valid),
                .fft_bin(fft_bin),
                .fft_sensor_id(fft_sensor_id),
                .fft_real(fft_real),
                .s_valid(spec_s_valid[s]),
                .s_ready(spec_s_ready[s]),
                .s_data(spec_s_data[s]),
                .s_last(spec_s_last[s])
            );

            spectrogram_generator #(
                .DATA_WIDTH(DATA_WIDTH),
                .BINS_PER_FRAME(SPEC_BINS),
                .FRAMES_PER_SPECTROGRAM(SPEC_FRAMES)
            ) u_spectrogram (
                .clk(clk),
                .reset(reset),
                .s_valid(spec_s_valid[s]),
                .s_ready(spec_s_ready[s]),
                .s_data(spec_s_data[s]),
                .s_last(spec_s_last[s]),
                .m_valid(spec_m_valid[s]),
                .m_ready(spec_m_ready[s]),
                .m_data(spec_m_data[s]),
                .m_last(spec_m_last[s])
            );
        end
    endgenerate

    // Backpressure the shared FFT with the spectrogram that owns the bin
    // currently on the bus. Bins at or above SPEC_BINS feed only the MLP
    // collector, which never stalls.
    always_comb begin
        if (fft_bin < 6'(SPEC_BINS)) fft_ready = spec_s_ready[fft_sensor_id];
        else                         fft_ready = 1'b1;
    end

    logic cnn_s_valid;
    logic cnn_s_ready;
    logic signed [DATA_WIDTH-1:0] cnn_s_data [0:N_VIB-1];
    logic cnn_s_last;
    logic spec_desync_error;

    spectrogram_4ch_join #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS(N_VIB)
    ) u_spec_join (
        .clk(clk),
        .reset(reset),
        .m_valid(spec_m_valid),
        .m_ready(spec_m_ready),
        .m_data(spec_m_data),
        .m_last(spec_m_last),
        .s_valid(cnn_s_valid),
        .s_ready(cnn_s_ready),
        .s_data(cnn_s_data),
        .s_last(cnn_s_last),
        .desync_error(spec_desync_error)
    );

    logic signed [DATA_WIDTH-1:0] cnn_normal;
    logic signed [DATA_WIDTH-1:0] cnn_unbalance;
    logic signed [DATA_WIDTH-1:0] cnn_misalign;
    logic signed [DATA_WIDTH-1:0] cnn_bearing;
    logic cnn_valid;

    cnn_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(SPEC_BINS),
        .IMG_HEIGHT(SPEC_FRAMES),
        .IN_CHANNELS(N_VIB),
        .CONV2_WEIGHTS_FILE(CONV2_WEIGHTS_FILE),
        .CONV2_BIASES_FILE(CONV2_BIASES_FILE),
        .DENSE_WEIGHTS_FILE(DENSE_WEIGHTS_FILE),
        .DENSE_BIASES_FILE(DENSE_BIASES_FILE)
    ) u_cnn (
        .clk(clk),
        .reset(reset),
        .s_valid(cnn_s_valid),
        .s_ready(cnn_s_ready),
        .s_data(cnn_s_data),
        .s_last(cnn_s_last),
        .m_valid(cnn_valid),
        .m_ready(1'b1), // Always ready to receive CNN inference
        .m_data_normal(cnn_normal),
        .m_data_unbalance(cnn_unbalance),
        .m_data_misalign(cnn_misalign),
        .m_data_bearing(cnn_bearing),
        .m_last()
    );

    // ------------------------------------------------------------------------
    // Decision Logic: Inference Arbiter
    // ------------------------------------------------------------------------
    inference_arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_SENSORS(N_VIB)
    ) u_inference_arbiter (
        .clk(clk),
        .reset(reset),
        .mlp_class_idx(mlp_class_idx),
        .mlp_sensor_id(mlp_result_sensor_id),
        .mlp_done(mlp_done),
        .cnn_normal(cnn_normal),
        .cnn_unbalance(cnn_unbalance),
        .cnn_misalign(cnn_misalign),
        .cnn_bearing(cnn_bearing),
        .cnn_valid(cnn_valid),
        .status_leds(status_leds),
        .sensor_fault_mask(sensor_fault_mask),
        .alert_flag(alert_flag)
    );

    // Sticky health flag: UART framing/checksum fault, dropped vibration
    // sample, MLP frame skipped because an inference was still running, or the
    // four spectrograms losing lockstep.
    //
    // sys_error e latcheado: o sensor_frame_error da UART e um PULSO de um
    // ciclo (erro de checksum ou ressincronizacao por timeout), e um OR
    // puramente combinacional deixaria esse pulso passar despercebido por
    // qualquer coisa que amostrasse sys_error alguns ciclos depois.
    always_ff @(posedge clk) begin
        if (reset) sys_error <= 1'b0;
        else if (sensor_frame_error | vib_overrun |
                 mlp_frame_dropped  | spec_desync_error)
            sys_error <= 1'b1;
    end

endmodule