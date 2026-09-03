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
// There is no LMS in this chain. preprocess_fft_shared_4sensor_q915_no_lms and
// preprocess_window_channel_no_lms have neither the filter nor a USE_LMS
// parameter -- that flag exists only in preprocess_lms_fft_four_modes.sv, the
// single-channel pipeline. Enabling an LMS here means adding it to the shared
// 4-channel chain, not flipping a parameter.
// ============================================================================
module dsp_preprocessing_subsystem #(
    parameter FIR_STAGE1_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage1_decim4_q117.bin",
    parameter FIR_STAGE2_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage2_decim4_q117.bin",
    parameter FIR_STAGE3_FILE = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage3_decim2_q117.bin",
    parameter HANN_FILE       = "../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/windowing/hann_64_q117.bin",
    parameter int NORMALIZE   = 1,
    parameter int HOP_SIZE    = 64
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
