`timescale 1ns/1ps

// Quatro canais Q9.15 sincronizados com uma unica FFT64 compartilhada.
// As quatro amostras sao aceitas atomicamente quando sample_valid e
// sample_ready estao ativos no mesmo ciclo.
module preprocess_fft_shared_4sensor_q915_no_lms #(
    parameter integer DATA_WIDTH = 24,
    parameter integer NORMALIZE  = 1,
    parameter integer HOP_SIZE   = 64,
`ifdef RTL_SIM
    parameter FIR_STAGE1_FILE = "coefficients/fir/stage1_decim4_q117.bin",
    parameter FIR_STAGE2_FILE = "coefficients/fir/stage2_decim4_q117.bin",
    parameter FIR_STAGE3_FILE = "coefficients/fir/stage3_decim2_q117.bin",
    parameter HANN_FILE       = "coefficients/windowing/hann_64_q117.bin"
`else
    parameter FIR_STAGE1_FILE = "../coefficients/fir/stage1_decim4_q117.bin",
    parameter FIR_STAGE2_FILE = "../coefficients/fir/stage2_decim4_q117.bin",
    parameter FIR_STAGE3_FILE = "../coefficients/fir/stage3_decim2_q117.bin",
    parameter HANN_FILE       = "../coefficients/windowing/hann_64_q117.bin"
`endif
)(
    input  wire                          clk,
    input  wire                          reset,

    input  wire signed [DATA_WIDTH-1:0] sensor1_sample,
    input  wire signed [DATA_WIDTH-1:0] sensor2_sample,
    input  wire signed [DATA_WIDTH-1:0] sensor3_sample,
    input  wire signed [DATA_WIDTH-1:0] sensor4_sample,
    input  wire                          sample_valid,
    output wire                          sample_ready,

    output wire                          fft_valid,
    input  wire                          fft_ready,
    output wire [5:0]                    fft_bin,
    output wire signed [DATA_WIDTH-1:0] fft_real,
    output wire signed [DATA_WIDTH-1:0] fft_imag,
    output wire [1:0]                    fft_sensor_id,
    output wire                          fft_done,
    output wire                          pipeline_busy,

    output wire [3:0]                    decimated_events,
    output wire [3:0]                    fir_stage1_saturation_events,
    output wire [3:0]                    fir_stage2_saturation_events,
    output wire [3:0]                    fir_stage3_saturation_events,
    output wire                          hann_saturation_event,
    output wire [1:0]                    hann_saturation_sensor_id,
    output wire                          fft_overflow_event,
    output wire [2:0]                    fft_overflow_stage,
    output wire [2:0]                    fft_overflow_components,
    output wire [1:0]                    fft_overflow_sensor_id
);

    wire [3:0] channel_input_ready;
    wire atomic_input_valid;
    assign sample_ready = &channel_input_ready;
    assign atomic_input_valid = sample_valid && sample_ready;

    wire signed [DATA_WIDTH-1:0] windowed_sample0;
    wire signed [DATA_WIDTH-1:0] windowed_sample1;
    wire signed [DATA_WIDTH-1:0] windowed_sample2;
    wire signed [DATA_WIDTH-1:0] windowed_sample3;
    wire [3:0] windowed_valid;
    wire [3:0] windowed_ready;
    wire [5:0] windowed_index0;
    wire [5:0] windowed_index1;
    wire [5:0] windowed_index2;
    wire [5:0] windowed_index3;
    wire [3:0] windowed_first;
    wire [3:0] windowed_last;
    wire [3:0] windowed_saturated;
    wire [3:0] channel_busy;

    preprocess_window_channel_no_lms #(
        .DATA_WIDTH       (DATA_WIDTH),
        .HOP_SIZE         (HOP_SIZE),
        .FIR_STAGE1_FILE  (FIR_STAGE1_FILE),
        .FIR_STAGE2_FILE  (FIR_STAGE2_FILE),
        .FIR_STAGE3_FILE  (FIR_STAGE3_FILE),
        .HANN_FILE        (HANN_FILE)
    ) channel0 (
        .clk                         (clk),
        .reset                       (reset),
        .sample_in                   (sensor1_sample),
        .sample_valid                (atomic_input_valid),
        .sample_ready                (channel_input_ready[0]),
        .windowed_sample             (windowed_sample0),
        .windowed_valid              (windowed_valid[0]),
        .windowed_ready              (windowed_ready[0]),
        .windowed_index              (windowed_index0),
        .windowed_first              (windowed_first[0]),
        .windowed_last               (windowed_last[0]),
        .windowed_saturated          (windowed_saturated[0]),
        .decimated_event             (decimated_events[0]),
        .fir_stage1_saturation_event (fir_stage1_saturation_events[0]),
        .fir_stage2_saturation_event (fir_stage2_saturation_events[0]),
        .fir_stage3_saturation_event (fir_stage3_saturation_events[0]),
        .channel_busy                (channel_busy[0])
    );

    preprocess_window_channel_no_lms #(
        .DATA_WIDTH       (DATA_WIDTH),
        .HOP_SIZE         (HOP_SIZE),
        .FIR_STAGE1_FILE  (FIR_STAGE1_FILE),
        .FIR_STAGE2_FILE  (FIR_STAGE2_FILE),
        .FIR_STAGE3_FILE  (FIR_STAGE3_FILE),
        .HANN_FILE        (HANN_FILE)
    ) channel1 (
        .clk                         (clk),
        .reset                       (reset),
        .sample_in                   (sensor2_sample),
        .sample_valid                (atomic_input_valid),
        .sample_ready                (channel_input_ready[1]),
        .windowed_sample             (windowed_sample1),
        .windowed_valid              (windowed_valid[1]),
        .windowed_ready              (windowed_ready[1]),
        .windowed_index              (windowed_index1),
        .windowed_first              (windowed_first[1]),
        .windowed_last               (windowed_last[1]),
        .windowed_saturated          (windowed_saturated[1]),
        .decimated_event             (decimated_events[1]),
        .fir_stage1_saturation_event (fir_stage1_saturation_events[1]),
        .fir_stage2_saturation_event (fir_stage2_saturation_events[1]),
        .fir_stage3_saturation_event (fir_stage3_saturation_events[1]),
        .channel_busy                (channel_busy[1])
    );

    preprocess_window_channel_no_lms #(
        .DATA_WIDTH       (DATA_WIDTH),
        .HOP_SIZE         (HOP_SIZE),
        .FIR_STAGE1_FILE  (FIR_STAGE1_FILE),
        .FIR_STAGE2_FILE  (FIR_STAGE2_FILE),
        .FIR_STAGE3_FILE  (FIR_STAGE3_FILE),
        .HANN_FILE        (HANN_FILE)
    ) channel2 (
        .clk                         (clk),
        .reset                       (reset),
        .sample_in                   (sensor3_sample),
        .sample_valid                (atomic_input_valid),
        .sample_ready                (channel_input_ready[2]),
        .windowed_sample             (windowed_sample2),
        .windowed_valid              (windowed_valid[2]),
        .windowed_ready              (windowed_ready[2]),
        .windowed_index              (windowed_index2),
        .windowed_first              (windowed_first[2]),
        .windowed_last               (windowed_last[2]),
        .windowed_saturated          (windowed_saturated[2]),
        .decimated_event             (decimated_events[2]),
        .fir_stage1_saturation_event (fir_stage1_saturation_events[2]),
        .fir_stage2_saturation_event (fir_stage2_saturation_events[2]),
        .fir_stage3_saturation_event (fir_stage3_saturation_events[2]),
        .channel_busy                (channel_busy[2])
    );

    preprocess_window_channel_no_lms #(
        .DATA_WIDTH       (DATA_WIDTH),
        .HOP_SIZE         (HOP_SIZE),
        .FIR_STAGE1_FILE  (FIR_STAGE1_FILE),
        .FIR_STAGE2_FILE  (FIR_STAGE2_FILE),
        .FIR_STAGE3_FILE  (FIR_STAGE3_FILE),
        .HANN_FILE        (HANN_FILE)
    ) channel3 (
        .clk                         (clk),
        .reset                       (reset),
        .sample_in                   (sensor4_sample),
        .sample_valid                (atomic_input_valid),
        .sample_ready                (channel_input_ready[3]),
        .windowed_sample             (windowed_sample3),
        .windowed_valid              (windowed_valid[3]),
        .windowed_ready              (windowed_ready[3]),
        .windowed_index              (windowed_index3),
        .windowed_first              (windowed_first[3]),
        .windowed_last               (windowed_last[3]),
        .windowed_saturated          (windowed_saturated[3]),
        .decimated_event             (decimated_events[3]),
        .fir_stage1_saturation_event (fir_stage1_saturation_events[3]),
        .fir_stage2_saturation_event (fir_stage2_saturation_events[3]),
        .fir_stage3_saturation_event (fir_stage3_saturation_events[3]),
        .channel_busy                (channel_busy[3])
    );

    wire shared_fft_busy;
    fft_shared_4sensor #(
        .DATA_WIDTH        (DATA_WIDTH),
        .NORMALIZE         (NORMALIZE),
        .COEFF_WIDTH       (18),
        .TWIDDLE_FRAC_BITS (17)
    ) shared_fft (
        .clk                        (clk),
        .reset                      (reset),

        .ch0_sample                 (windowed_sample0),
        .ch0_valid                  (windowed_valid[0]),
        .ch0_ready                  (windowed_ready[0]),
        .ch0_index                  (windowed_index0),
        .ch0_first                  (windowed_first[0]),
        .ch0_last                   (windowed_last[0]),
        .ch0_saturated              (windowed_saturated[0]),

        .ch1_sample                 (windowed_sample1),
        .ch1_valid                  (windowed_valid[1]),
        .ch1_ready                  (windowed_ready[1]),
        .ch1_index                  (windowed_index1),
        .ch1_first                  (windowed_first[1]),
        .ch1_last                   (windowed_last[1]),
        .ch1_saturated              (windowed_saturated[1]),

        .ch2_sample                 (windowed_sample2),
        .ch2_valid                  (windowed_valid[2]),
        .ch2_ready                  (windowed_ready[2]),
        .ch2_index                  (windowed_index2),
        .ch2_first                  (windowed_first[2]),
        .ch2_last                   (windowed_last[2]),
        .ch2_saturated              (windowed_saturated[2]),

        .ch3_sample                 (windowed_sample3),
        .ch3_valid                  (windowed_valid[3]),
        .ch3_ready                  (windowed_ready[3]),
        .ch3_index                  (windowed_index3),
        .ch3_first                  (windowed_first[3]),
        .ch3_last                   (windowed_last[3]),
        .ch3_saturated              (windowed_saturated[3]),

        .fft_valid                  (fft_valid),
        .fft_ready                  (fft_ready),
        .fft_bin                    (fft_bin),
        .fft_real                   (fft_real),
        .fft_imag                   (fft_imag),
        .fft_sensor_id              (fft_sensor_id),
        .fft_done                   (fft_done),
        .fft_busy                   (shared_fft_busy),
        .hann_saturation_event      (hann_saturation_event),
        .hann_saturation_sensor_id  (hann_saturation_sensor_id),
        .fft_overflow_event         (fft_overflow_event),
        .fft_overflow_stage         (fft_overflow_stage),
        .fft_overflow_components    (fft_overflow_components),
        .fft_overflow_sensor_id     (fft_overflow_sensor_id)
    );

    assign pipeline_busy = (|channel_busy) || shared_fft_busy ||
                           !sample_ready;

    // synthesis translate_off
    always @(posedge clk) begin
        if (!reset && sample_valid && sample_ready) begin
            if (channel_input_ready !== 4'b1111)
                $fatal(1, "[shared_4sensor] Aceitacao nao atomica.");
        end
    end
    // synthesis translate_on

endmodule
