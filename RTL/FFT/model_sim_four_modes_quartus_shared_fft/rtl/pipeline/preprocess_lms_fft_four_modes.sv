`timescale 1ns/1ps

// Cadeia integrada usada pelos quatro modos:
//   FIR/32 -> LMS opcional -> frame64/hop8 -> media -> Hann -> FFT64.
module preprocess_lms_fft_four_modes #(
    parameter integer DATA_WIDTH      = 24,
    parameter integer FRAC_BITS       = 15,
    parameter integer NORMALIZE       = 1,
    parameter integer USE_LMS         = 0,
    parameter integer MU_SHIFT        = 16,
    parameter integer HOP_SIZE        = 8,
    parameter FIR_STAGE1_FILE =
        "../coefficients/fir/stage1_decim4_q117.bin",
    parameter FIR_STAGE2_FILE =
        "../coefficients/fir/stage2_decim4_q117.bin",
    parameter FIR_STAGE3_FILE =
        "../coefficients/fir/stage3_decim2_q117.bin",
    parameter HANN_FILE =
        "../coefficients/windowing/hann_64_q117.bin"
)(
    input  wire                           clk,
    input  wire                           reset,

    input  wire signed [DATA_WIDTH-1:0]  desired_sample,
    input  wire                           desired_valid,
    output wire                           desired_ready,
    input  wire signed [DATA_WIDTH-1:0]  reference_sample,
    input  wire                           reference_valid,
    output wire                           reference_ready,

    input  wire                           adapt_enable,
    input  wire                           clear_coefficients,

    output wire                           fft_valid,
    input  wire                           fft_ready,
    output wire [5:0]                     fft_bin,
    output wire signed [DATA_WIDTH-1:0]   fft_real,
    output wire signed [DATA_WIDTH-1:0]   fft_imag,
    output wire                           fft_done,
    output wire                           pipeline_busy,

    output wire                           desired_decimated_event,
    output wire                           reference_decimated_event,
    output wire                           lms_input_event,
    output wire                           lms_output_event,
    output wire                           desired_fir_stage1_saturation_event,
    output wire                           desired_fir_stage2_saturation_event,
    output wire                           desired_fir_stage3_saturation_event,
    output wire                           reference_fir_stage1_saturation_event,
    output wire                           reference_fir_stage2_saturation_event,
    output wire                           reference_fir_stage3_saturation_event,
    output wire                           lms_error_saturated,
    output wire                           lms_estimate_saturated,
    output wire                           lms_coefficient_saturated,
    output wire                           hann_saturation_event,
    output wire                           fft_overflow_event,
    output wire [2:0]                     fft_overflow_stage,
    output wire [2:0]                     fft_overflow_components
);

    localparam integer LMS_COEFF_WIDTH =
        (DATA_WIDTH > 24) ? DATA_WIDTH : 24;
    localparam integer CORRECTED_WIDTH = DATA_WIDTH + 1;

    wire desired_fir_input_valid;
    wire desired_fir_input_ready;
    wire signed [DATA_WIDTH-1:0] desired_decimated;
    wire desired_decimated_valid;
    wire desired_decimated_ready;

    fir_decimator_32_dualmode #(
        .SAMPLE_WIDTH       (DATA_WIDTH),
        .COEFF_WIDTH        (18),
        .ACC_WIDTH          (64),
        .COEFF_FRAC_BITS    (17),
        .STAGE1_INIT_FILE   (FIR_STAGE1_FILE),
        .STAGE2_INIT_FILE   (FIR_STAGE2_FILE),
        .STAGE3_INIT_FILE   (FIR_STAGE3_FILE)
    ) desired_decimator (
        .clk                     (clk),
        .reset                   (reset),
        .sample_in               (desired_sample),
        .sample_valid            (desired_fir_input_valid),
        .sample_ready            (desired_fir_input_ready),
        .sample_out              (desired_decimated),
        .sample_out_valid        (desired_decimated_valid),
        .sample_out_ready        (desired_decimated_ready),
        .stage1_saturation_event (desired_fir_stage1_saturation_event),
        .stage2_saturation_event (desired_fir_stage2_saturation_event),
        .stage3_saturation_event (desired_fir_stage3_saturation_event)
    );

    wire signed [DATA_WIDTH-1:0] stream_to_buffer;
    wire stream_to_buffer_valid;
    wire stream_to_buffer_ready;
    wire lms_busy_internal;

    generate
        if (USE_LMS != 0) begin : gen_lms
            wire reference_fir_input_valid;
            wire reference_fir_input_ready;
            wire signed [DATA_WIDTH-1:0] reference_decimated;
            wire reference_decimated_valid;
            wire reference_decimated_ready;
            wire lms_desired_ready;
            wire lms_reference_ready;
            wire signed [DATA_WIDTH-1:0] lms_error;
            wire signed [DATA_WIDTH-1:0] lms_estimate;
            wire lms_error_valid;

            // Join atomico: nenhum arquivo avanca sem que os dois
            // decimadores possam aceitar a mesma amostra temporal.
            assign desired_fir_input_valid =
                desired_valid && reference_valid &&
                reference_fir_input_ready;
            assign reference_fir_input_valid =
                desired_valid && reference_valid &&
                desired_fir_input_ready;
            assign desired_ready =
                reference_valid && desired_fir_input_ready &&
                reference_fir_input_ready;
            assign reference_ready =
                desired_valid && desired_fir_input_ready &&
                reference_fir_input_ready;

            fir_decimator_32_dualmode #(
                .SAMPLE_WIDTH       (DATA_WIDTH),
                .COEFF_WIDTH        (18),
                .ACC_WIDTH          (64),
                .COEFF_FRAC_BITS    (17),
                .STAGE1_INIT_FILE   (FIR_STAGE1_FILE),
                .STAGE2_INIT_FILE   (FIR_STAGE2_FILE),
                .STAGE3_INIT_FILE   (FIR_STAGE3_FILE)
            ) reference_decimator (
                .clk                     (clk),
                .reset                   (reset),
                .sample_in               (reference_sample),
                .sample_valid            (reference_fir_input_valid),
                .sample_ready            (reference_fir_input_ready),
                .sample_out              (reference_decimated),
                .sample_out_valid        (reference_decimated_valid),
                .sample_out_ready        (reference_decimated_ready),
                .stage1_saturation_event (reference_fir_stage1_saturation_event),
                .stage2_saturation_event (reference_fir_stage2_saturation_event),
                .stage3_saturation_event (reference_fir_stage3_saturation_event)
            );

            lms_filter_8tap_dualmode #(
                .SAMPLE_WIDTH      (DATA_WIDTH),
                .SAMPLE_FRAC_BITS  (FRAC_BITS),
                .COEFF_WIDTH       (LMS_COEFF_WIDTH),
                .COEFF_FRAC_BITS   (20),
                .ACC_WIDTH         (64),
                .MU_SHIFT          (MU_SHIFT)
            ) lms_filter (
                .clk                    (clk),
                .reset                  (reset),
                .desired_sample         (desired_decimated),
                .desired_valid          (desired_decimated_valid),
                .desired_ready          (lms_desired_ready),
                .reference_sample       (reference_decimated),
                .reference_valid        (reference_decimated_valid),
                .reference_ready        (lms_reference_ready),
                .adapt_enable           (adapt_enable),
                .clear_coefficients     (clear_coefficients),
                .error_sample           (lms_error),
                .noise_estimate         (lms_estimate),
                .error_valid            (lms_error_valid),
                .error_ready            (stream_to_buffer_ready),
                .busy                   (lms_busy_internal),
                .error_saturated        (lms_error_saturated),
                .estimate_saturated     (lms_estimate_saturated),
                .coefficient_saturated  (lms_coefficient_saturated),
                .coeff0_out(), .coeff1_out(), .coeff2_out(), .coeff3_out(),
                .coeff4_out(), .coeff5_out(), .coeff6_out(), .coeff7_out()
            );

            assign desired_decimated_ready = lms_desired_ready;
            assign reference_decimated_ready = lms_reference_ready;
            assign stream_to_buffer = lms_error;
            assign stream_to_buffer_valid = lms_error_valid;
            assign desired_decimated_event =
                desired_decimated_valid && desired_decimated_ready;
            assign reference_decimated_event =
                reference_decimated_valid && reference_decimated_ready;
            assign lms_input_event =
                desired_decimated_valid && lms_desired_ready &&
                reference_decimated_valid && lms_reference_ready;
            assign lms_output_event =
                lms_error_valid && stream_to_buffer_ready;
        end
        else begin : gen_no_lms
            assign desired_fir_input_valid = desired_valid;
            assign desired_ready = desired_fir_input_ready;
            assign reference_ready = 1'b0;
            assign desired_decimated_ready = stream_to_buffer_ready;
            assign stream_to_buffer = desired_decimated;
            assign stream_to_buffer_valid = desired_decimated_valid;
            assign desired_decimated_event =
                desired_decimated_valid && desired_decimated_ready;
            assign reference_decimated_event = 1'b0;
            assign lms_input_event = 1'b0;
            assign lms_output_event = 1'b0;
            assign lms_busy_internal = 1'b0;
            assign lms_error_saturated = 1'b0;
            assign lms_estimate_saturated = 1'b0;
            assign lms_coefficient_saturated = 1'b0;
            assign reference_fir_stage1_saturation_event = 1'b0;
            assign reference_fir_stage2_saturation_event = 1'b0;
            assign reference_fir_stage3_saturation_event = 1'b0;
        end
    endgenerate

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
        .sample_in          (stream_to_buffer),
        .sample_valid       (stream_to_buffer_valid),
        .sample_ready       (stream_to_buffer_ready),
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

    wire signed [DATA_WIDTH-1:0] windowed_sample;
    wire windowed_valid;
    wire windowed_ready;
    wire [5:0] windowed_index;
    wire windowed_first;
    wire windowed_last;
    wire windowed_saturated;

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

    localparam [1:0] LOADER_LOAD  = 2'd0;
    localparam [1:0] LOADER_START = 2'd1;
    localparam [1:0] LOADER_WAIT  = 2'd2;
    reg [1:0] loader_state;

    wire fft_load_ready;
    wire fft_busy_internal;
    wire fft_start;

    assign windowed_ready =
        (loader_state == LOADER_LOAD) && fft_load_ready;
    assign hann_saturation_event =
        windowed_valid && windowed_ready && windowed_saturated;
    assign fft_start = (loader_state == LOADER_START);

    always @(posedge clk) begin
        if (reset)
            loader_state <= LOADER_LOAD;
        else begin
            case (loader_state)
                LOADER_LOAD: begin
                    if (windowed_valid && windowed_ready && windowed_last)
                        loader_state <= LOADER_START;
                end
                LOADER_START: loader_state <= LOADER_WAIT;
                LOADER_WAIT: begin
                    if (fft_done)
                        loader_state <= LOADER_LOAD;
                end
                default: loader_state <= LOADER_LOAD;
            endcase
        end
    end

    fft_64_dualmode #(
        .INPUT_WIDTH       (DATA_WIDTH),
        .FFT_WIDTH         (DATA_WIDTH),
        .COEFF_WIDTH       (18),
        .TWIDDLE_FRAC_BITS (17),
        .NORMALIZE         (NORMALIZE)
    ) fft_core (
        .clk                       (clk),
        .reset                     (reset),
        .load_en                   (windowed_valid && windowed_ready),
        .load_addr                 (windowed_index),
        .load_data                 (windowed_sample),
        .load_ready                (fft_load_ready),
        .start                     (fft_start),
        .busy                      (fft_busy_internal),
        .done                      (fft_done),
        .fft_valid                 (fft_valid),
        .fft_ready                 (fft_ready),
        .fft_bin_out               (fft_bin),
        .fft_real_out              (fft_real),
        .fft_imag_out              (fft_imag),
        .overflow_event            (fft_overflow_event),
        .overflow_stage            (fft_overflow_stage),
        .overflow_components       (fft_overflow_components),
        .overflow_total_components (),
        .probe_event               (),
        .probe_stage               (),
        .probe_top_real            (),
        .probe_top_imag            (),
        .probe_bottom_real         (),
        .probe_bottom_imag         ()
    );

    assign pipeline_busy =
        lms_busy_internal || frame_buffer_busy || mean_busy ||
        fft_busy_internal || (loader_state != LOADER_LOAD);

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && windowed_valid && windowed_ready) begin
            if (windowed_first !== (windowed_index == 6'd0))
                $fatal(1,
                    "[preprocess_lms_fft] Marcador first inconsistente.");
            if (windowed_last !== (windowed_index == 6'd63))
                $fatal(1,
                    "[preprocess_lms_fft] Marcador last inconsistente.");
        end
    end
`endif

endmodule
