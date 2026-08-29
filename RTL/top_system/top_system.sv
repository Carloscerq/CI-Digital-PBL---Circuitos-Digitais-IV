`timescale 1ns / 1ps

// ============================================================================
// Top Level System
// ============================================================================
// Nine sensors arrive over one SPI slave port, framed one chip-select
// assertion per acquisition epoch:
//
//   4 x vibration  -> shared 64-point FFT -> { MLP , spectrogram + CNN }
//   3 x current    \
//   2 x temperature -> MLP extra features (4 of the 5 are used, see EXTRA_SEL)
//
// Only the vibration channels need the FFT, and they share ONE fft_64 core:
// preprocess_fft_shared_4sensor_q915_no_lms keeps four independent
// FIR/frame/mean/Hann front-ends but round-robins a single FFT between them,
// tagging every output bin with `fft_sensor_id`.
//
// That single tagged stream fans out to both inference paths:
//
//   Path A (MLP)  one 132-feature buffer, time-multiplexed over the four
//                 sensors -- one inference per completed FFT frame.
//   Path B (CNN)  four private spectrograms, one per sensor, joined into the
//                 CNN's four input channels so a whole beat is one pixel of
//                 all four sensors.
// ============================================================================
module top_system #(
    parameter int DATA_WIDTH = 24
)(
    input  logic clk,
    input  logic reset,                 // Synchronous active-high reset

    // SPI slave pins -- every sensor value arrives here
    input  logic spi_serial_clock,
    input  logic spi_slave_select_n,
    input  logic spi_mosi,
    output logic spi_miso,

    // Decision outputs
    output logic [2:0] status_leds,     // [2]=Critical, [1]=Warning, [0]=Normal
    output logic [3:0] sensor_fault_mask,
    output logic       alert_flag,
    output logic       sys_error        // sticky: framing / overrun / desync
);

    // ------------------------------------------------------------------------
    // Sensor map. Word order inside one SPI frame.
    // ------------------------------------------------------------------------
    localparam int N_VIB     = 4;   // vibration    -> FFT
    localparam int N_CUR     = 3;   // current      -> MLP extras
    localparam int N_TMP     = 2;   // temperature  -> MLP extras
    localparam int N_SENSORS = N_VIB + N_CUR + N_TMP;   // 9
    localparam int N_AUX     = N_CUR + N_TMP;           // 5

    localparam int SPEC_BINS   = 32;  // bins per spectrogram row  (CNN width)
    localparam int SPEC_FRAMES = 32;  // rows per spectrogram      (CNN height)

    // ------------------------------------------------------------------------
    // SPI Data Ingestion
    // ------------------------------------------------------------------------
    logic [7:0] spi_data_out;
    logic       spi_data_valid;
    logic       spi_busy;

    spi_slave #(
        .SIZE(8),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) u_spi_slave (
        .clk(clk),
        .reset(reset),
        .data_in(8'd0), // Not transmitting data back for now
        .data_out(spi_data_out),
        .data_valid(spi_data_valid),
        .busy(spi_busy),
        .serial_clock(spi_serial_clock),
        .slave_in_controller_out(spi_mosi),
        .controller_in_slave_out(spi_miso),
        .slave_select_n(spi_slave_select_n)
    );

    logic signed [DATA_WIDTH-1:0] sensor_data [0:N_SENSORS-1];
    logic sensor_frame_valid;
    logic sensor_frame_error;

    spi_sensor_frame_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_SENSORS(N_SENSORS),
        .BYTES_PER_WORD(DATA_WIDTH/8)
    ) u_frame_rx (
        .clk(clk),
        .reset(reset),
        .spi_data(spi_data_out),
        .spi_valid(spi_data_valid),
        .spi_selected(spi_busy),
        .sensor_data(sensor_data),
        .frame_valid(sensor_frame_valid),
        .frame_error(sensor_frame_error)
    );

    // Non-vibration sensors go straight to the MLP feature collector, which
    // samples them once per FFT frame. aux index 0..2 = current, 3..4 = temp.
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
    // SPI cannot be back-pressured, so the four vibration samples are held in
    // a one-deep register until the pipeline accepts them atomically. The FIR
    // front-end is decimate-by-32, so it drains far faster than SPI fills;
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
    // Path A: MLP, time-multiplexed over the four sensors
    // ------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] mlp_features [132];
    logic mlp_start;
    logic [1:0] mlp_sensor_id;
    logic mlp_busy_internal;
    logic mlp_frame_dropped;

    fft_to_mlp_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_AUX(N_AUX)
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
        .mlp_features(mlp_features),
        .mlp_start(mlp_start),
        .mlp_sensor_id(mlp_sensor_id),
        .mlp_busy(mlp_busy_internal),
        .frame_dropped(mlp_frame_dropped)
    );

    logic signed [DATA_WIDTH-1:0] mlp_logits [4];
    logic [1:0] mlp_class_idx;
    logic mlp_done;

    mlp u_mlp (
        .clk(clk),
        .reset(reset),
        .start(mlp_start),
        .features(mlp_features),
        .logits(mlp_logits),
        .class_idx(mlp_class_idx),
        .busy(mlp_busy_internal),
        .done(mlp_done)
    );

    // The MLP result belongs to the frame that was being collected, so tag it
    // with the sensor id captured at that frame's first bin.
    logic [1:0] mlp_result_sensor_id;
    always_ff @(posedge clk) begin
        if (reset)             mlp_result_sensor_id <= 2'd0;
        else if (mlp_start)    mlp_result_sensor_id <= mlp_sensor_id;
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

    smma_cnn_top #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(SPEC_BINS),
        .IMG_HEIGHT(SPEC_FRAMES),
        .IN_CHANNELS(N_VIB)
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

    // Sticky health flag: SPI framing fault, dropped vibration sample, MLP
    // frame skipped because an inference was still running, or the four
    // spectrograms losing lockstep.
    assign sys_error = sensor_frame_error | vib_overrun |
                       mlp_frame_dropped  | spec_desync_error;

endmodule
