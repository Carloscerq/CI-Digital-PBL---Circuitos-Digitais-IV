`timescale 1ns / 1ps

// ============================================================================
// cnn_inference_path
// ============================================================================
// Path B: four per-sensor spectrograms, joined into the CNN's four input
// channels, double-buffered as whole frames, then classified.
//
//   beat stream -> 4x fft_to_stream_adapter -> 4x spectrogram_generator
//               -> spectrogram_4ch_join -> frame_pingpong_buffer -> cnn_top
//
// >>> BACKPRESSURE_NOTE <<<
// This path owns `s_ready` for the whole FFT fork: it is the only consumer
// that can stall. Bins at or above SPEC_BINS are the conjugate mirror, feed
// only the MLP path, and are accepted unconditionally. The ready reaching the
// FFT is registered inside dsp_preprocessing_subsystem's skid buffer, so this
// mux no longer sits on the FFT's own flow-control path.
//
// >>> FRAME_BUFFER_NOTE <<<
// frame_pingpong_buffer holds two complete 32 x 32 x 4 frames between the join
// and the CNN. The CNN needs thousands of cycles per frame, which a depth-2
// skid buffer could not absorb; with the frame buffer in place the joiner can
// drain all four generators at full rate as soon as they align, and release
// their read banks without waiting for the CNN.
// ============================================================================
module cnn_inference_path #(
    parameter CONV2_WEIGHTS_FILE = "../mem/cnn/conv2d_weights.mem",
    parameter CONV2_BIASES_FILE  = "../mem/cnn/conv2d_biases.mem",
    parameter DENSE_WEIGHTS_FILE = "../mem/cnn/dense_weights.mem",
    parameter DENSE_BIASES_FILE  = "../mem/cnn/dense_biases.mem"
)(
    input  logic clk,
    input  logic reset,                          // synchronous, active high

    // Buffered FFT beat stream. This path drives the shared accept.
    input  system_types_pkg::fft_beat_t s_beat,
    input  logic                        s_valid,
    output logic                        s_ready,

    // Verdict: one set of logits per spectrogram, all four sensors fused
    output system_types_pkg::sample_t cnn_normal,
    output system_types_pkg::sample_t cnn_unbalance,
    output system_types_pkg::sample_t cnn_misalign,
    output system_types_pkg::sample_t cnn_bearing,
    output logic                      cnn_valid,

    // Diagnostics
    output logic spec_desync_error,              // sticky
    output logic cnn_stall_event                 // sticky: CNN back-pressured the FFT
);

    import system_types_pkg::*;

    // ------------------------------------------------------------------
    // Per-sensor spectrogram front ends
    // ------------------------------------------------------------------
    logic [N_VIB-1:0]             spec_s_valid;
    logic [N_VIB-1:0]             spec_s_ready;
    logic signed [DATA_WIDTH-1:0] spec_s_data [0:N_VIB-1];
    logic [N_VIB-1:0]             spec_s_last;

    logic [N_VIB-1:0]             spec_m_valid;
    logic [N_VIB-1:0]             spec_m_ready;
    logic signed [DATA_WIDTH-1:0] spec_m_data [0:N_VIB-1];
    logic [N_VIB-1:0]             spec_m_last;

    genvar s;
    generate
        for (s = 0; s < N_VIB; s++) begin : g_spec
            fft_to_stream_adapter #(
                .DATA_WIDTH            (DATA_WIDTH),
                .BINS_PER_FRAME        (SPEC_BINS),
                .FRAMES_PER_SPECTROGRAM(SPEC_FRAMES),
                .SENSOR_ID             (s)
            ) u_fft_to_spec_adapter (
                .clk          (clk),
                .reset        (reset),
                .fft_valid    (s_valid),
                .fft_bin      (s_beat.bin),
                .fft_sensor_id(s_beat.sensor_id),
                .fft_real     (s_beat.re),
                .s_valid      (spec_s_valid[s]),
                .s_ready      (spec_s_ready[s]),
                .s_data       (spec_s_data[s]),
                .s_last       (spec_s_last[s])
            );

            spectrogram_generator #(
                .DATA_WIDTH            (DATA_WIDTH),
                .BINS_PER_FRAME        (SPEC_BINS),
                .FRAMES_PER_SPECTROGRAM(SPEC_FRAMES)
            ) u_spectrogram (
                .clk    (clk),
                .reset  (reset),
                .s_valid(spec_s_valid[s]),
                .s_ready(spec_s_ready[s]),
                .s_data (spec_s_data[s]),
                .s_last (spec_s_last[s]),
                .m_valid(spec_m_valid[s]),
                .m_ready(spec_m_ready[s]),
                .m_data (spec_m_data[s]),
                .m_last (spec_m_last[s])
            );
        end
    endgenerate

    // Back-pressure the shared FFT with the spectrogram that owns the bin
    // currently on the bus. See BACKPRESSURE_NOTE.
    always_comb begin
        if (s_beat.bin < FFT_BIN_W'(SPEC_BINS)) s_ready = spec_s_ready[s_beat.sensor_id];
        else                                    s_ready = 1'b1;
    end

    // ------------------------------------------------------------------
    // Lockstep join -> whole-frame double buffer -> CNN
    // ------------------------------------------------------------------
    logic                         join_valid;
    logic                         join_ready;
    logic signed [DATA_WIDTH-1:0] join_data [0:N_VIB-1];
    logic                         join_last;

    spectrogram_4ch_join #(
        .DATA_WIDTH(DATA_WIDTH),
        .CHANNELS  (N_VIB)
    ) u_spec_join (
        .clk         (clk),
        .reset       (reset),
        .m_valid     (spec_m_valid),
        .m_ready     (spec_m_ready),
        .m_data      (spec_m_data),
        .m_last      (spec_m_last),
        .s_valid     (join_valid),
        .s_ready     (join_ready),
        .s_data      (join_data),
        .s_last      (join_last),
        .desync_error(spec_desync_error)
    );

    logic                         cnn_s_valid;
    logic                         cnn_s_ready;
    logic signed [DATA_WIDTH-1:0] cnn_s_data [0:N_VIB-1];
    logic                         cnn_s_last;

    frame_pingpong_buffer #(
        .DATA_WIDTH (DATA_WIDTH),
        .CHANNELS   (N_VIB),
        .FRAME_WORDS(SPEC_WORDS)
    ) u_frame_buffer (
        .clk          (clk),
        .reset        (reset),
        .s_valid      (join_valid),
        .s_ready      (join_ready),
        .s_data       (join_data),
        .s_last       (join_last),
        .m_valid      (cnn_s_valid),
        .m_ready      (cnn_s_ready),
        .m_data       (cnn_s_data),
        .m_last       (cnn_s_last),
        .stall_event  (cnn_stall_event)
    );

    cnn_top #(
        .DATA_WIDTH        (DATA_WIDTH),
        .IMG_WIDTH         (SPEC_BINS),
        .IMG_HEIGHT        (SPEC_FRAMES),
        .IN_CHANNELS       (N_VIB),
        .CONV2_WEIGHTS_FILE(CONV2_WEIGHTS_FILE),
        .CONV2_BIASES_FILE (CONV2_BIASES_FILE),
        .DENSE_WEIGHTS_FILE(DENSE_WEIGHTS_FILE),
        .DENSE_BIASES_FILE (DENSE_BIASES_FILE)
    ) u_cnn (
        .clk             (clk),
        .reset           (reset),
        .s_valid         (cnn_s_valid),
        .s_ready         (cnn_s_ready),
        .s_data          (cnn_s_data),
        .s_last          (cnn_s_last),
        .m_valid         (cnn_valid),
        .m_ready         (1'b1),      // the arbiter latches on valid
        .m_data_normal   (cnn_normal),
        .m_data_unbalance(cnn_unbalance),
        .m_data_misalign (cnn_misalign),
        .m_data_bearing  (cnn_bearing),
        .m_last          ()
    );

endmodule
