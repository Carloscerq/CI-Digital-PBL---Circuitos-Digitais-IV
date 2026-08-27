module quartus_pipeline_q915_no_lms_4sensor_shared_top (
    input  wire                 clk,
    input  wire                 reset,

    input  wire signed [23:0]   sensor1_sample,
    input  wire signed [23:0]   sensor2_sample,
    input  wire signed [23:0]   sensor3_sample,
    input  wire signed [23:0]   sensor4_sample,
    input  wire                 sample_valid,
    output wire                 sample_ready,

    output wire                 fft_valid,
    input  wire                 fft_ready,
    output wire [5:0]           fft_bin,
    output wire signed [23:0]   fft_real,
    output wire signed [23:0]   fft_imag,
    output wire [1:0]           fft_sensor_id,
    output wire                 fft_done,
    output wire                 pipeline_busy,

    output wire                 fft_overflow_event,
    output wire [2:0]           fft_overflow_stage,
    output wire [2:0]           fft_overflow_components,
    output wire [1:0]           fft_overflow_sensor_id
);

    preprocess_fft_shared_4sensor_q915_no_lms #(
        .DATA_WIDTH (24),
        .NORMALIZE  (1),
        .HOP_SIZE   (64)
    ) pipeline (
        .clk                          (clk),
        .reset                        (reset),
        .sensor1_sample               (sensor1_sample),
        .sensor2_sample               (sensor2_sample),
        .sensor3_sample               (sensor3_sample),
        .sensor4_sample               (sensor4_sample),
        .sample_valid                 (sample_valid),
        .sample_ready                 (sample_ready),
        .fft_valid                    (fft_valid),
        .fft_ready                    (fft_ready),
        .fft_bin                      (fft_bin),
        .fft_real                     (fft_real),
        .fft_imag                     (fft_imag),
        .fft_sensor_id                (fft_sensor_id),
        .fft_done                     (fft_done),
        .pipeline_busy                (pipeline_busy),
        .decimated_events             (),
        .fir_stage1_saturation_events (),
        .fir_stage2_saturation_events (),
        .fir_stage3_saturation_events (),
        .hann_saturation_event        (),
        .hann_saturation_sensor_id    (),
        .fft_overflow_event           (fft_overflow_event),
        .fft_overflow_stage           (fft_overflow_stage),
        .fft_overflow_components      (fft_overflow_components),
        .fft_overflow_sensor_id       (fft_overflow_sensor_id)
    );

endmodule
