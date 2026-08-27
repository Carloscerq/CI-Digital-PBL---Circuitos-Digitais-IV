`timescale 1ns/1ps

// Canal de pre-processamento sem LMS:
// FIR/32 -> frame64/hop -> remocao da media -> Hann.
//
// O canal termina em uma interface serial ready/valid de 64 amostras. Isso
// permite que quatro canais independentes compartilhem uma unica FFT.
module preprocess_window_channel_no_lms #(
    parameter integer DATA_WIDTH = 24,
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
    input  wire                           clk,
    input  wire                           reset,

    input  wire signed [DATA_WIDTH-1:0]  sample_in,
    input  wire                           sample_valid,
    output wire                           sample_ready,

    output wire signed [DATA_WIDTH-1:0]  windowed_sample,
    output wire                           windowed_valid,
    input  wire                           windowed_ready,
    output wire [5:0]                     windowed_index,
    output wire                           windowed_first,
    output wire                           windowed_last,
    output wire                           windowed_saturated,

    output wire                           decimated_event,
    output wire                           fir_stage1_saturation_event,
    output wire                           fir_stage2_saturation_event,
    output wire                           fir_stage3_saturation_event,
    output wire                           channel_busy
);

    localparam integer CORRECTED_WIDTH = DATA_WIDTH + 1;

    wire signed [DATA_WIDTH-1:0] decimated_sample;
    wire decimated_valid;
    wire decimated_ready;

    fir_decimator_32_dualmode #(
        .SAMPLE_WIDTH       (DATA_WIDTH),
        .COEFF_WIDTH        (18),
        .ACC_WIDTH          (64),
        .COEFF_FRAC_BITS    (17),
        .STAGE1_INIT_FILE   (FIR_STAGE1_FILE),
        .STAGE2_INIT_FILE   (FIR_STAGE2_FILE),
        .STAGE3_INIT_FILE   (FIR_STAGE3_FILE)
    ) decimator (
        .clk                     (clk),
        .reset                   (reset),
        .sample_in               (sample_in),
        .sample_valid            (sample_valid),
        .sample_ready            (sample_ready),
        .sample_out              (decimated_sample),
        .sample_out_valid        (decimated_valid),
        .sample_out_ready        (decimated_ready),
        .stage1_saturation_event (fir_stage1_saturation_event),
        .stage2_saturation_event (fir_stage2_saturation_event),
        .stage3_saturation_event (fir_stage3_saturation_event)
    );

    wire signed [DATA_WIDTH-1:0] frame_sample;
    wire frame_sample_valid;
    wire frame_sample_ready;
    wire [5:0] frame_sample_index;
    wire frame_sample_first;
    wire frame_sample_last;
    wire frame_buffer_busy;

    sample_buffer_64_hop_dualmode #(
        .SAMPLE_WIDTH (DATA_WIDTH),
        .HOP_SIZE     (HOP_SIZE)
    ) frame_buffer (
        .clk                (clk),
        .reset              (reset),
        .sample_in          (decimated_sample),
        .sample_valid       (decimated_valid),
        .sample_ready       (decimated_ready),
        .frame_sample_out   (frame_sample),
        .frame_sample_valid (frame_sample_valid),
        .frame_sample_ready (frame_sample_ready),
        .frame_sample_index (frame_sample_index),
        .frame_sample_first (frame_sample_first),
        .frame_sample_last  (frame_sample_last),
        .buffer_full        (),
        .frame_busy         (frame_buffer_busy)
    );

    wire signed [CORRECTED_WIDTH-1:0] corrected_sample;
    wire corrected_valid;
    wire corrected_ready;
    wire [5:0] corrected_index;
    wire corrected_first;
    wire corrected_last;
    wire mean_busy;

    mean_remover_64_dualmode #(
        .SAMPLE_WIDTH (DATA_WIDTH)
    ) mean_remover (
        .clk                    (clk),
        .reset                  (reset),
        .frame_sample_in        (frame_sample),
        .frame_sample_valid     (frame_sample_valid),
        .frame_sample_ready     (frame_sample_ready),
        .corrected_sample_out   (corrected_sample),
        .corrected_sample_valid (corrected_valid),
        .corrected_sample_ready (corrected_ready),
        .corrected_sample_index (corrected_index),
        .corrected_sample_first (corrected_first),
        .corrected_sample_last  (corrected_last),
        .frame_mean             (),
        .frame_mean_valid       (),
        .frame_busy             (mean_busy)
    );

    hann_window_64_dualmode #(
        .INPUT_WIDTH       (CORRECTED_WIDTH),
        .COEFF_WIDTH       (18),
        .OUTPUT_WIDTH      (DATA_WIDTH),
        .COEFF_FRAC_BITS   (17),
        .INIT_FILE         (HANN_FILE)
    ) hann_window (
        .clk                       (clk),
        .reset                     (reset),
        .sample_in                 (corrected_sample),
        .sample_valid              (corrected_valid),
        .sample_ready              (corrected_ready),
        .sample_index              (corrected_index),
        .sample_first              (corrected_first),
        .sample_last               (corrected_last),
        .windowed_sample_out       (windowed_sample),
        .windowed_sample_valid     (windowed_valid),
        .windowed_sample_ready     (windowed_ready),
        .windowed_sample_index     (windowed_index),
        .windowed_sample_first     (windowed_first),
        .windowed_sample_last      (windowed_last),
        .windowed_sample_saturated (windowed_saturated)
    );

    assign decimated_event = decimated_valid && decimated_ready;
    assign channel_busy = frame_buffer_busy || mean_busy || windowed_valid;

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH <= 1)
            $fatal(1, "[preprocess_window_channel] DATA_WIDTH invalido.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1, "[preprocess_window_channel] HOP_SIZE invalido.");
    end
    // synthesis translate_on

endmodule
