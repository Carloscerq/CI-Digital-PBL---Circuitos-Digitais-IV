`timescale 1ns / 1ps

// ============================================================================
// dsp_preprocessing_subsystem
// ============================================================================
// The four vibration channels and the single shared 64-point FFT, presented to
// the inference paths as one registered beat stream.
//
// >>> DECOUPLING_NOTE <<<
// The output skid buffer is the whole point of this wrapper. Previously
// top_system drove the FFT's `fft_ready` from a combinational mux over the
// four spectrogram write-side ready signals, so the CNN path's flow control
// reached back into the FFT output FSM through logic. The skid buffer makes
// `fft_ready` a registered signal in both directions at the cost of one cycle
// of latency.
//
// >>> FFT_DONE_NOTE <<<
// The pipeline's own `fft_done` is deliberately left UNCONNECTED. It fires in
// the FFT core's S_DONE state, two cycles after the last bin transfers and
// with fft_valid already low, so it rides no beat and would overtake bins
// still sitting in the skid buffer. The frame boundary crosses the buffer as
// the `last` bit of the beat carrying bin FFT_N-1 instead, and `m_frame_done`
// is regenerated from that on the downstream side.
//
// >>> LMS_NOTE <<<
// The two shared 4-channel pipelines are separate modules, not one module with
// a flag, so USE_LMS picks between them in a generate:
//
//   USE_LMS = 1 -> preprocess_fft_shared_4sensor_q915_lms
//                  [FIR/32 or bypass] -> LMS -> frame64 -> mean -> Hann
//   USE_LMS = 0 -> preprocess_fft_shared_4sensor_q915_no_lms
//                  FIR/32 -> frame64 -> mean -> Hann
//
// The LMS is an 8-tap time-domain linear predictor and the framer is fed its
// ERROR, not its prediction -- so what reaches the FFT is the part of the
// signal the predictor could NOT explain from the previous 8 samples. That
// whitens the stream: broadband content survives, narrowband tonal content is
// attenuated. Worth knowing which way round it is, because the 1x and 2x shaft
// tones that identify unbalance and misalignment are the tonal part.
//
// >>> LMS_STEP_NOTE <<<
// LMS_MU_SHIFT sets the adaptation rate, and the right value depends on
// USE_DECIMATOR. The coefficient update is
// (e * x) >>> (2*15 + LMS_MU_SHIFT - 20), a shift of 26 at the default 16, so
// whether it does anything depends on how big |e*x| is. The FIR is a lowpass:
// it drops the signal's standard deviation by roughly 28x and |e*x| by about
// 2^10. Measured on real captures:
//
//   USE_DECIMATOR = 0, raw 25.6 kHz : |e*x| ~ 2^30..2^36, residual 0.69..0.87
//   USE_DECIMATOR = 1, decimated    : |e*x| ~ 2^20..2^25, residual 0.99+
//
// So 16 is matched to the BYPASS path, where the filter genuinely adapts and
// is worth 22 points of classification accuracy. Behind the decimator every
// update truncates to zero and the filter is a no-op; the equivalent step
// there is LMS_MU_SHIFT around 6.
//
// >>> LIVE BUILD <<< system_types_pkg has DECIM_RATE = 32, so the LMS sits
// behind the decimator and at LMS_MU_SHIFT = 16 it is a NO-OP: measured
// 87.5% with it against 87.7% without, which is inside the seed spread. It
// costs eight multiply-accumulate state machines and buys nothing in this
// configuration. Set USE_LMS = 0 to reclaim that, or accept it as harmless.
//
// Do not just turn it up. Mild whitening helps, aggressive whitening does not:
// the tonal 1x and 2x shaft content it removes is what unbalance and
// misalignment are made of, and pushing the step past those values costs
// accuracy in both builds.
//
// One detail for the starved regime: the update uses an arithmetic (floor)
// shift, so a sub-LSB update rounds to 0 for a positive product and -1 for a
// negative one, and the taps ratchet downward rather than sitting still. Every
// other shift in this front end rounds half away from zero.
//
// >>> DECIMATOR_NOTE <<<
// USE_DECIMATOR = 0 bypasses fir_decimator_32_dualmode, so the FFT sees the
// raw 25.6 kHz stream. See BIN_SPACING_NOTE in system_types_pkg -- that is
// 400 Hz per bin instead of 12.5 Hz, and it puts the entire diagnostic band in
// bin 0. Only the _lms pipeline has the bypass; the _no_lms one always
// decimates, so USE_DECIMATOR is ignored when USE_LMS = 0.
// ============================================================================
module dsp_preprocessing_subsystem #(
    parameter FIR_STAGE1_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage1_decim4_q117.bin",
    parameter FIR_STAGE2_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage2_decim4_q117.bin",
    parameter FIR_STAGE3_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage3_decim2_q117.bin",
    parameter HANN_FILE       = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/windowing/hann_64_q117.bin",
    parameter int NORMALIZE     = 1,
    parameter int HOP_SIZE      = 64,
    parameter bit USE_LMS       = 1'b1,   // see LMS_NOTE
    parameter bit USE_DECIMATOR = 1'b1,   // see DECIMATOR_NOTE
    parameter int LMS_MU_SHIFT  = 16      // see LMS_STEP_NOTE
)(
    input  logic clk,
    input  logic reset,                          // synchronous, active high

    // Vibration quad in
    input  system_types_pkg::vib_bus_t s_vib_data,
    input  logic                       s_vib_valid,
    output logic                       s_vib_ready,

    // Registered FFT beat stream out
    output system_types_pkg::fft_beat_t m_beat,
    output logic                        m_valid,
    input  logic                        m_ready,
    output logic                        m_frame_done   // one sensor's 64 bins done
);

    import system_types_pkg::*;

    // ------------------------------------------------------------------
    // Shared FFT front end
    // ------------------------------------------------------------------
    logic                          fft_valid;
    logic                          fft_ready;
    logic [FFT_BIN_W-1:0]          fft_bin;
    logic signed [DATA_WIDTH-1:0]  fft_real;
    logic signed [DATA_WIDTH-1:0]  fft_imag;
    logic [SID_W-1:0]              fft_sensor_id;

    // Unpacked into explicit wires rather than calling vib_get() inside the
    // port map: a function call in a port connection is legal but is exactly
    // the kind of construct Quartus Standard handles inconsistently.
    logic signed [DATA_WIDTH-1:0] vib_sample [0:N_VIB-1];

    genvar g;
    generate
        for (g = 0; g < N_VIB; g++) begin : g_vib_unpack
            assign vib_sample[g] = vib_get(s_vib_data, g);
        end
    endgenerate

    // The coefficient paths are resolved by Quartus relative to the project
    // directory (RTL/quartus/); the module defaults assume the FFT's own
    // project, so they are overridden from the top level.
    //
    // Both branches expose the same signals to the rest of this file. The
    // event outputs are left unconnected here exactly as before; the LMS
    // branch simply has four more of them.
    generate
        if (USE_LMS) begin : g_lms_pipeline
            preprocess_fft_shared_4sensor_q915_lms #(
                .DATA_WIDTH     (DATA_WIDTH),
                .NORMALIZE      (NORMALIZE),
                .HOP_SIZE       (HOP_SIZE),
                .LMS_MU_SHIFT   (LMS_MU_SHIFT),
                .USE_DECIMATOR  (USE_DECIMATOR ? 1 : 0),
                .FIR_STAGE1_FILE(FIR_STAGE1_FILE),
                .FIR_STAGE2_FILE(FIR_STAGE2_FILE),
                .FIR_STAGE3_FILE(FIR_STAGE3_FILE),
                .HANN_FILE      (HANN_FILE)
            ) u_fft_pipeline (
                .clk  (clk),
                .reset(reset),

                .sensor1_sample(vib_sample[0]),
                .sensor2_sample(vib_sample[1]),
                .sensor3_sample(vib_sample[2]),
                .sensor4_sample(vib_sample[3]),
                .sample_valid  (s_vib_valid),
                .sample_ready  (s_vib_ready),

                // Adapt continuously and never clear, matching the standalone
                // top the FFT project ships.
                .lms_adapt_enable      (1'b1),
                .lms_clear_coefficients(1'b0),

                .fft_valid    (fft_valid),
                .fft_ready    (fft_ready),
                .fft_bin      (fft_bin),
                .fft_real     (fft_real),
                .fft_imag     (fft_imag),
                .fft_sensor_id(fft_sensor_id),
                .fft_done     (),               // see FFT_DONE_NOTE
                .pipeline_busy(),

                // Debug and event flags left unconnected for brevity
                .decimated_events                 (),
                .lms_output_events                (),
                .lms_error_saturation_events      (),
                .lms_prediction_saturation_events (),
                .lms_coefficient_saturation_events(),
                .fir_stage1_saturation_events     (),
                .fir_stage2_saturation_events     (),
                .fir_stage3_saturation_events     (),
                .hann_saturation_event            (),
                .hann_saturation_sensor_id        (),
                .fft_overflow_event               (),
                .fft_overflow_stage               (),
                .fft_overflow_components          (),
                .fft_overflow_sensor_id           ()
            );
        end
        else begin : g_plain_pipeline
            preprocess_fft_shared_4sensor_q915_no_lms #(
                .DATA_WIDTH     (DATA_WIDTH),
                .NORMALIZE      (NORMALIZE),
                .HOP_SIZE       (HOP_SIZE),
                .FIR_STAGE1_FILE(FIR_STAGE1_FILE),
                .FIR_STAGE2_FILE(FIR_STAGE2_FILE),
                .FIR_STAGE3_FILE(FIR_STAGE3_FILE),
                .HANN_FILE      (HANN_FILE)
            ) u_fft_pipeline (
                .clk  (clk),
                .reset(reset),

                .sensor1_sample(vib_sample[0]),
                .sensor2_sample(vib_sample[1]),
                .sensor3_sample(vib_sample[2]),
                .sensor4_sample(vib_sample[3]),
                .sample_valid  (s_vib_valid),
                .sample_ready  (s_vib_ready),

                .fft_valid    (fft_valid),
                .fft_ready    (fft_ready),
                .fft_bin      (fft_bin),
                .fft_real     (fft_real),
                .fft_imag     (fft_imag),
                .fft_sensor_id(fft_sensor_id),
                .fft_done     (),               // see FFT_DONE_NOTE
                .pipeline_busy(),

                // Debug and event flags left unconnected for brevity
                .decimated_events            (),
                .fir_stage1_saturation_events(),
                .fir_stage2_saturation_events(),
                .fir_stage3_saturation_events(),
                .hann_saturation_event       (),
                .hann_saturation_sensor_id   (),
                .fft_overflow_event          (),
                .fft_overflow_stage          (),
                .fft_overflow_components     (),
                .fft_overflow_sensor_id      ()
            );
        end
    endgenerate

    // ------------------------------------------------------------------
    // Beat packing and the registered boundary
    // ------------------------------------------------------------------
    fft_beat_t             raw_beat;
    logic [FFT_BEAT_W-1:0] raw_bits;
    logic [FFT_BEAT_W-1:0] beat_bits;

    always_comb begin
        raw_beat.sensor_id = fft_sensor_id;
        raw_beat.bin       = fft_bin;
        raw_beat.im        = fft_imag;
        raw_beat.re        = fft_real;
        raw_beat.last      = (fft_bin == FFT_BIN_W'(FFT_N-1));
    end

    // A packed struct IS a vector of the same width, so this needs no cast.
    assign raw_bits = raw_beat;

    skid_buffer #(
        .WIDTH(FFT_BEAT_W)
    ) u_fft_skid (
        .clk    (clk),
        .reset  (reset),
        .s_valid(fft_valid),
        .s_ready(fft_ready),
        .s_data (raw_bits),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data (beat_bits)
    );

    assign m_beat       = fft_beat_t'(beat_bits);
    assign m_frame_done = m_valid && m_ready && m_beat.last;

endmodule
