`timescale 1ns/1ps

// Canal de pre-processamento com LMS temporal.
// USE_DECIMATOR=1: FIR/32 -> LMS -> frame64/hop -> media -> Hann.
// USE_DECIMATOR=0: entrada -> LMS -> frame64/hop -> media -> Hann.
//
// error_sample do LMS e encaminhado ao buffer. prediction_sample permanece
// interno e representa a componente temporal prevista pelo filtro.
module preprocess_window_channel_lms #(
    parameter integer DATA_WIDTH      = 24,
    parameter integer HOP_SIZE        = 64,
    parameter integer LMS_MU_SHIFT    = 16,
    parameter integer USE_DECIMATOR   = 1,
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

    input  wire                           lms_adapt_enable,
    input  wire                           lms_clear_coefficients,

    output wire signed [DATA_WIDTH-1:0]  windowed_sample,
    output wire                           windowed_valid,
    input  wire                           windowed_ready,
    output wire [5:0]                     windowed_index,
    output wire                           windowed_first,
    output wire                           windowed_last,
    output wire                           windowed_saturated,

    output wire                           decimated_event,
    output wire                           lms_output_event,
    output wire                           lms_error_saturation_event,
    output wire                           lms_prediction_saturation_event,
    output wire                           lms_coefficient_saturation_event,
    output wire                           fir_stage1_saturation_event,
    output wire                           fir_stage2_saturation_event,
    output wire                           fir_stage3_saturation_event,
    output wire                           channel_busy
);

    localparam integer CORRECTED_WIDTH = DATA_WIDTH + 1;

    // ------------------------------------------------------------------------
    // Entrada do LMS. No modo normal vem do decimador /32. No modo bypass,
    // a interface ready/valid da entrada e ligada diretamente ao LMS.
    // ------------------------------------------------------------------------
    wire signed [DATA_WIDTH-1:0] lms_input_sample;
    wire                         lms_input_valid;
    wire                         lms_input_ready;

    generate
        if (USE_DECIMATOR != 0) begin : generate_decimator
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
                .sample_out              (lms_input_sample),
                .sample_out_valid        (lms_input_valid),
                .sample_out_ready        (lms_input_ready),
                .stage1_saturation_event (fir_stage1_saturation_event),
                .stage2_saturation_event (fir_stage2_saturation_event),
                .stage3_saturation_event (fir_stage3_saturation_event)
            );

            assign decimated_event = lms_input_valid && lms_input_ready;
        end
        else begin : generate_decimator_bypass
            assign lms_input_sample = sample_in;
            assign lms_input_valid  = sample_valid;
            assign sample_ready     = lms_input_ready;

            // Mantem a interface e os contadores compativeis. Neste modo,
            // decimated_event significa "amostra aceita no bypass".
            assign decimated_event = sample_valid && sample_ready;
            assign fir_stage1_saturation_event = 1'b0;
            assign fir_stage2_saturation_event = 1'b0;
            assign fir_stage3_saturation_event = 1'b0;
        end
    endgenerate

    // ------------------------------------------------------------------------
    // LMS temporal de 8 taps. Um operador de multiplicacao e reutilizado.
    // ------------------------------------------------------------------------
    wire signed [DATA_WIDTH-1:0] lms_error_sample;
    wire signed [DATA_WIDTH-1:0] lms_prediction_sample;
    wire lms_valid;
    wire lms_ready;
    wire lms_busy;
    wire lms_error_saturated;
    wire lms_prediction_saturated;
    wire lms_coefficient_saturated;

    lms_filter_time_serial #(
        .DATA_WIDTH       (DATA_WIDTH),
        .DATA_FRAC_BITS   (15),
        .COEFF_FRAC_BITS  (20),
        .ACC_WIDTH        (52),
        .MU_SHIFT         (LMS_MU_SHIFT)
    ) lms_filter (
        .clk                    (clk),
        .reset                  (reset),
        .sample_in              (lms_input_sample),
        .sample_valid           (lms_input_valid),
        .sample_ready           (lms_input_ready),
        .adapt_enable           (lms_adapt_enable),
        .clear_coefficients     (lms_clear_coefficients),
        .error_sample           (lms_error_sample),
        .prediction_sample      (lms_prediction_sample),
        .output_valid           (lms_valid),
        .output_ready           (lms_ready),
        .busy                   (lms_busy),
        .error_saturated        (lms_error_saturated),
        .estimate_saturated     (lms_prediction_saturated),
        .coefficient_saturated  (lms_coefficient_saturated)
    );

    // ------------------------------------------------------------------------
    // Formacao de frames de 64 amostras a partir do residual do LMS.
    // ------------------------------------------------------------------------
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
        .sample_in          (lms_error_sample),
        .sample_valid       (lms_valid),
        .sample_ready       (lms_ready),
        .frame_sample_out   (frame_sample),
        .frame_sample_valid (frame_sample_valid),
        .frame_sample_ready (frame_sample_ready),
        .frame_sample_index (frame_sample_index),
        .frame_sample_first (frame_sample_first),
        .frame_sample_last  (frame_sample_last),
        .buffer_full        (),
        .frame_busy         (frame_buffer_busy)
    );

    // ------------------------------------------------------------------------
    // Remocao da media do frame.
    // ------------------------------------------------------------------------
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

    // ------------------------------------------------------------------------
    // Janela de Hann.
    // ------------------------------------------------------------------------
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

    assign lms_output_event = lms_valid && lms_ready;
    assign lms_error_saturation_event =
        lms_valid && lms_ready && lms_error_saturated;
    assign lms_prediction_saturation_event =
        lms_valid && lms_ready && lms_prediction_saturated;
    assign lms_coefficient_saturation_event =
        lms_valid && lms_ready && lms_coefficient_saturated;

    assign channel_busy = lms_busy || frame_buffer_busy || mean_busy ||
                          windowed_valid;

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != 24)
            $fatal(1, "[preprocess_window_channel_lms] DATA_WIDTH deve ser 24.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1, "[preprocess_window_channel_lms] HOP_SIZE invalido.");
        if (LMS_MU_SHIFT < 1)
            $fatal(1, "[preprocess_window_channel_lms] LMS_MU_SHIFT invalido.");
        if (USE_DECIMATOR != 0 && USE_DECIMATOR != 1)
            $fatal(1, "[preprocess_window_channel_lms] USE_DECIMATOR deve ser 0 ou 1.");
    end
    // synthesis translate_on

endmodule
