module quartus_pipeline_q915_no_lms_top (
    input  wire                 clk,
    input  wire                 reset,

    input  wire signed [23:0]   sample_in,
    input  wire                 sample_valid,
    output wire                 sample_ready,

    output wire                 fft_valid,
    input  wire                 fft_ready,
    output wire [5:0]           fft_bin,
    output wire signed [23:0]   fft_real,
    output wire signed [23:0]   fft_imag,
    output wire                 fft_done,
    output wire                 pipeline_busy,

    output wire                 fft_overflow_event,
    output wire [2:0]           fft_overflow_stage,
    output wire [2:0]           fft_overflow_components
);

    preprocess_lms_fft_four_modes #(
        .DATA_WIDTH (24),
        .FRAC_BITS  (15),
        .NORMALIZE  (1),
        .USE_LMS    (0),
        .MU_SHIFT   (16),
        .HOP_SIZE   (64)
    ) pipeline (
        .clk                       (clk),
        .reset                     (reset),

        .desired_sample            (sample_in),
        .desired_valid             (sample_valid),
        .desired_ready             (sample_ready),

        // Referência não utilizada porque USE_LMS=0.
        .reference_sample          (24'sd0),
        .reference_valid           (1'b0),
        .reference_ready           (),

        .adapt_enable              (1'b0),
        .clear_coefficients        (1'b0),

        .fft_valid                 (fft_valid),
        .fft_ready                 (fft_ready),
        .fft_bin                   (fft_bin),
        .fft_real                  (fft_real),
        .fft_imag                  (fft_imag),
        .fft_done                  (fft_done),
        .pipeline_busy             (pipeline_busy),

        .desired_decimated_event   (),
        .reference_decimated_event (),
        .lms_input_event           (),
        .lms_output_event          (),

        .desired_fir_stage1_saturation_event (),
        .desired_fir_stage2_saturation_event (),
        .desired_fir_stage3_saturation_event (),
        .reference_fir_stage1_saturation_event (),
        .reference_fir_stage2_saturation_event (),
        .reference_fir_stage3_saturation_event (),

        .lms_error_saturated       (),
        .lms_estimate_saturated    (),
        .lms_coefficient_saturated (),
        .hann_saturation_event     (),

        .fft_overflow_event        (fft_overflow_event),
        .fft_overflow_stage        (fft_overflow_stage),
        .fft_overflow_components   (fft_overflow_components)
    );

endmodule