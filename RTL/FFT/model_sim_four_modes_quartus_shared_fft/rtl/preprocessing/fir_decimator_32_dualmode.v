`timescale 1ns/1ps

// Decimador FIR multietapas /32:
//   25,6 kHz --/4--> 6,4 kHz --/4--> 1,6 kHz --/2--> 800 Hz.
// Amostras: Q9.15 (24 bits) ou Q11.16 (27 bits).
// Coeficientes: Q1.17 (18 bits) em ambos os modos.
module fir_decimator_32_dualmode #(
    parameter integer SAMPLE_WIDTH      = 24,
    parameter integer COEFF_WIDTH       = 18,
    parameter integer ACC_WIDTH         = 64,
    parameter integer COEFF_FRAC_BITS   = 17,
    parameter STAGE1_INIT_FILE =
        "../coefficients/fir/stage1_decim4_q117.bin",
    parameter STAGE2_INIT_FILE =
        "../coefficients/fir/stage2_decim4_q117.bin",
    parameter STAGE3_INIT_FILE =
        "../coefficients/fir/stage3_decim2_q117.bin"
)(
    input  wire                            clk,
    input  wire                            reset,
    input  wire signed [SAMPLE_WIDTH-1:0]  sample_in,
    input  wire                            sample_valid,
    output wire                            sample_ready,
    output wire signed [SAMPLE_WIDTH-1:0]  sample_out,
    output wire                            sample_out_valid,
    input  wire                            sample_out_ready,
    output wire                            stage1_saturation_event,
    output wire                            stage2_saturation_event,
    output wire                            stage3_saturation_event
);

    localparam integer COEFF_ADDR_WIDTH = 7;

    wire signed [SAMPLE_WIDTH-1:0] stage1_data;
    wire signed [SAMPLE_WIDTH-1:0] stage2_data;
    wire signed [SAMPLE_WIDTH-1:0] stage3_data;
    wire stage1_valid;
    wire stage2_valid;
    wire stage3_valid;
    wire stage1_ready;
    wire stage2_ready;
    wire stage1_saturated;
    wire stage2_saturated;
    wire stage3_saturated;

    fir_decimator_stage_dualmode #(
        .SAMPLE_WIDTH      (SAMPLE_WIDTH),
        .COEFF_WIDTH       (COEFF_WIDTH),
        .ACC_WIDTH         (ACC_WIDTH),
        .COEFF_FRAC_BITS   (COEFF_FRAC_BITS),
        .NUM_TAPS          (47),
        .DECIMATION        (4),
        .COEFF_ADDR_WIDTH  (COEFF_ADDR_WIDTH),
        .INIT_FILE         (STAGE1_INIT_FILE)
    ) stage1 (
        .clk                  (clk),
        .reset                (reset),
        .sample_in            (sample_in),
        .sample_valid         (sample_valid),
        .sample_ready         (sample_ready),
        .sample_out           (stage1_data),
        .sample_out_valid     (stage1_valid),
        .sample_out_ready     (stage1_ready),
        .sample_out_saturated (stage1_saturated)
    );

    fir_decimator_stage_dualmode #(
        .SAMPLE_WIDTH      (SAMPLE_WIDTH),
        .COEFF_WIDTH       (COEFF_WIDTH),
        .ACC_WIDTH         (ACC_WIDTH),
        .COEFF_FRAC_BITS   (COEFF_FRAC_BITS),
        .NUM_TAPS          (67),
        .DECIMATION        (4),
        .COEFF_ADDR_WIDTH  (COEFF_ADDR_WIDTH),
        .INIT_FILE         (STAGE2_INIT_FILE)
    ) stage2 (
        .clk                  (clk),
        .reset                (reset),
        .sample_in            (stage1_data),
        .sample_valid         (stage1_valid),
        .sample_ready         (stage1_ready),
        .sample_out           (stage2_data),
        .sample_out_valid     (stage2_valid),
        .sample_out_ready     (stage2_ready),
        .sample_out_saturated (stage2_saturated)
    );

    fir_decimator_stage_dualmode #(
        .SAMPLE_WIDTH      (SAMPLE_WIDTH),
        .COEFF_WIDTH       (COEFF_WIDTH),
        .ACC_WIDTH         (ACC_WIDTH),
        .COEFF_FRAC_BITS   (COEFF_FRAC_BITS),
        .NUM_TAPS          (83),
        .DECIMATION        (2),
        .COEFF_ADDR_WIDTH  (COEFF_ADDR_WIDTH),
        .INIT_FILE         (STAGE3_INIT_FILE)
    ) stage3 (
        .clk                  (clk),
        .reset                (reset),
        .sample_in            (stage2_data),
        .sample_valid         (stage2_valid),
        .sample_ready         (stage2_ready),
        .sample_out           (stage3_data),
        .sample_out_valid     (stage3_valid),
        .sample_out_ready     (sample_out_ready),
        .sample_out_saturated (stage3_saturated)
    );

    assign sample_out = stage3_data;
    assign sample_out_valid = stage3_valid;

    // Pulsos contabilizados apenas quando a amostra saturada e transferida.
    assign stage1_saturation_event =
        stage1_valid && stage1_ready && stage1_saturated;
    assign stage2_saturation_event =
        stage2_valid && stage2_ready && stage2_saturated;
    assign stage3_saturation_event =
        stage3_valid && sample_out_ready && stage3_saturated;

`ifndef SYNTHESIS
    initial begin
        if (SAMPLE_WIDTH != 24 && SAMPLE_WIDTH != 27)
            $warning(
                "[fir_decimator_32_dualmode] SAMPLE_WIDTH=%0d; modos validados usam 24 ou 27 bits.",
                SAMPLE_WIDTH);
        if (COEFF_WIDTH != 18 || COEFF_FRAC_BITS != 17)
            $fatal(1,
                "[fir_decimator_32_dualmode] Arquivos fornecidos exigem coeficientes Q1.17/18 bits.");
    end
`endif

endmodule
