`timescale 1ns / 1ps

// ============================================================================
// mlp_inference_path
// ============================================================================
// Path A: spectral peak detection and GCD (the MDC module), feature assembly,
// and the MLP itself. One inference per ROUND of the four vibration sensors.
//
// >>> SNOOP_NOTE <<<
// This path is a pure consumer of the FFT beat stream and never stalls it. It
// observes `s_valid` and `s_ready`, but `s_ready` is driven by
// cnn_inference_path, which is the only consumer with real backpressure. That
// keeps the fork single-master: one accept signal, both paths see the same
// beats on the same cycles. The MLP itself is decoupled from beat arrival by
// the collector's ping-pong feature banks, so a busy engine can no longer cost
// a whole round.
// ============================================================================
module mlp_inference_path #(
    parameter int MDC_K_MAX = 26,      // notebook MDC_K_MAX
    parameter int MDC_K_MIN = 2,       // notebook MDC_K_MIN
    parameter int MDC_PEAKS = 3        // notebook MDC_N_PEAKS
)(
    input  logic clk,
    input  logic reset,                          // synchronous, active high

    // Buffered FFT beat stream (shared accept)
    input  system_types_pkg::fft_beat_t s_beat,
    input  logic                        s_valid,
    input  logic                        s_ready,
    input  logic                        s_frame_done,

    // Frame aggregates, latest value
    input  system_types_pkg::aux_bus_t  aux_data,

    // Verdict: a class for the WHOLE machine, not for one sensor
    output logic [1:0] mlp_class_idx,
    output logic       mlp_done,

    // Diagnostics
    output system_types_pkg::sample_t mdc_k0,
    output logic                      mdc_valid,     // low => rotation never locked
    output logic                      mdc_overrun,   // sticky
    output logic                      frame_dropped  // sticky
);

    import system_types_pkg::*;
    import mlp_weights_pkg::N_IN;
    import mlp_weights_pkg::N_OUT;
    import mlp_weights_pkg::ACC_WIDTH;

    // ------------------------------------------------------------------
    // Spectral peaks -> GCD -> fundamental rotation bin k0
    // ------------------------------------------------------------------
    logic mdc_update;

    fft_peak_mdc #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_VIB     (N_VIB),
        .K_MAX     (MDC_K_MAX),
        .K_MIN     (MDC_K_MIN),
        .N_PEAKS   (MDC_PEAKS)
    ) u_peak_mdc (
        .clk          (clk),
        .reset        (reset),
        .fft_valid    (s_valid),
        .fft_ready    (s_ready),
        .fft_bin      (s_beat.bin),
        .fft_real     (s_beat.re),
        .fft_imag     (s_beat.im),
        .fft_sensor_id(s_beat.sensor_id),
        .fft_done     (s_frame_done),
        .mdc_k0       (mdc_k0),
        .mdc_valid    (mdc_valid),
        .mdc_update   (mdc_update),
        .mdc_overrun  (mdc_overrun)
    );

    // ------------------------------------------------------------------
    // Feature assembly
    // ------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] aux_features [0:N_AUX-1];

    genvar a;
    generate
        for (a = 0; a < N_AUX; a++) begin : g_aux_unpack
            assign aux_features[a] = aux_get(aux_data, a);
        end
    endgenerate

    logic signed [ACC_WIDTH-1:0] mlp_features [N_IN];
    logic                        mlp_start;
    logic                        mlp_busy;

    fft_to_mlp_collector #(
        .DATA_WIDTH   (DATA_WIDTH),
        .N_VIB        (N_VIB),
        .BINS_USED    (SPEC_BINS),   // 32 useful bins per sensor
        .N_AUX        (N_AUX),
        // aux 0 = current, 1 = temp A, 2 = temp B; the model wants
        // (Temp A, Temp B, U-phase_pow) -> '{1, 2, 0}
        .EXTRA_SEL    ('{1, 2, 0}),
        .USE_MAGNITUDE(1)
    ) u_feature_collector (
        .clk          (clk),
        .reset        (reset),
        .fft_valid    (s_valid),
        .fft_ready    (s_ready),
        .fft_bin      (s_beat.bin),
        .fft_real     (s_beat.re),
        .fft_imag     (s_beat.im),
        .fft_done     (s_frame_done),
        .fft_sensor_id(s_beat.sensor_id),
        .aux_features (aux_features),
        .mdc_k0       (mdc_k0),
        .mlp_features (mlp_features),
        .mlp_start    (mlp_start),
        .mlp_busy     (mlp_busy),
        .frame_dropped(frame_dropped)
    );

    // ------------------------------------------------------------------
    // Inference
    // ------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] mlp_logits [N_OUT];   // debug only

    mlp u_mlp (
        .clk      (clk),
        .reset    (reset),
        .start    (mlp_start),
        .features (mlp_features),
        .logits   (mlp_logits),
        .class_idx(mlp_class_idx),
        .busy     (mlp_busy),
        .done     (mlp_done)
    );

endmodule
