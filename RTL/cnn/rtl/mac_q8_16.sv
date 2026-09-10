`timescale 1ns / 1ps

// ============================================================================
// Saturating multiply-accumulate
// ============================================================================
// >>> FRAC_BITS_NOTE <<<
// FRAC_BITS is the scale of the WEIGHT operand, not the sample format. The
// activation's own Q9.15 cancels through the shift:
//
//   a = X * 2^15  (Q9.15 activation)      b = W * 2^FRAC_BITS  (weight)
//   sum(a*b) >> FRAC_BITS = sum(X*W) * 2^15, i.e. Q9.15 again
//
// So FRAC_BITS only has to match how the host quantised the weights. It is 15
// because Scripts/cnn/cnn_train.ipynb exports at 2^15; sweeping it 13..20
// changes no classification, because the error is dominated by activation
// truncation rather than weight resolution.
//
// The BIAS does not cancel. conv2d_fsm and dense_layer_fsm inject it as
// bias * (1 << FRAC_BITS) so the same shift returns it untouched, which means
// the bias code must already be in the activation format (Q9.15). Quantise the
// weights and the bias at different scales from FRAC_BITS and the bias moves
// relative to the activations -- measured at 2^15 weights against FRAC_BITS=16,
// that doubled the bias and changed 46.7% of predictions.
//
// >>> ACC_WIDTH_NOTE <<<
// The accumulator is PROD_WIDTH + ACC_GUARD bits. It used to be exactly
// PROD_WIDTH (48), which cannot hold the dense layer's worst case: a 47-bit
// product summed 2049 times reaches 2^57. Real data stayed near 2^37.4, so it
// never wrapped in practice, but the failure mode is a SILENT wraparound --
// the saturation logic below inspects the extraction bits and cannot see a
// carry that has already been lost. ACC_GUARD = 12 covers 2049 terms with
// room to spare and costs 12 flip-flops per MAC.
// ============================================================================
module mac_q8_16 #(
    parameter int DATA_WIDTH = 24,
    parameter int FRAC_BITS  = 15,   // see FRAC_BITS_NOTE
    parameter int ACC_GUARD  = 12    // see ACC_WIDTH_NOTE
)(
    input  logic               clk,
    input  logic               reset,
    input  logic               en,
    input  logic               clr, // Clears the accumulator
    input  logic signed [DATA_WIDTH-1:0] a,
    input  logic signed [DATA_WIDTH-1:0] b,
    output logic signed [DATA_WIDTH-1:0] out
);

    localparam int PROD_WIDTH = DATA_WIDTH * 2;
    localparam int ACC_WIDTH  = PROD_WIDTH + ACC_GUARD;

    // Pipeline registers to ensure proper DSP48 inference (3 stages)
    logic signed [DATA_WIDTH-1:0] a_reg;
    logic signed [DATA_WIDTH-1:0] b_reg;
    logic               clr_reg1;
    logic               clr_reg2;
    (* multstyle = "dsp" *) logic signed [PROD_WIDTH-1:0] mult_reg;
    logic signed [ACC_WIDTH-1:0] acc_reg;

    // Sign-extended product, written out rather than relying on an implicit
    // width cast: the explicit form is the one every tool agrees on.
    logic signed [ACC_WIDTH-1:0] mult_ext;
    assign mult_ext = {{(ACC_WIDTH-PROD_WIDTH){mult_reg[PROD_WIDTH-1]}}, mult_reg};

    always_ff @(posedge clk) begin
        if (reset) begin
            a_reg    <= '0;
            b_reg    <= '0;
            clr_reg1 <= '0;
            clr_reg2 <= '0;
            mult_reg <= '0;
            acc_reg  <= '0;
        end else if (en) begin
            // Stage 1: Input registers
            a_reg    <= a;
            b_reg    <= b;
            clr_reg1 <= clr;
            
            // Stage 2: Multiplier register (M-reg in DSP48)
            mult_reg <= a_reg * b_reg;
            clr_reg2 <= clr_reg1;

            // Stage 3: Accumulator register (P-reg in DSP48)
            if (clr_reg2) begin
                acc_reg <= mult_ext;
            end else begin
                acc_reg <= acc_reg + mult_ext;
            end
        end
    end

    // Combinational logic for safely extracting the parameterized fixed-point result
    // from the extended accumulator, applying saturation.
    logic signed [DATA_WIDTH-1:0] truncated_out;
    logic overflow;
    logic underflow;

    always_comb begin
        truncated_out = acc_reg[FRAC_BITS + DATA_WIDTH - 1 : FRAC_BITS];
        
        // Overflow detection:
        // If the number is positive (acc_reg[ACC_WIDTH-1] == 0), all upper bits must be 0.
        // If the number is negative (acc_reg[ACC_WIDTH-1] == 1), all upper bits must be 1.
        if (!acc_reg[ACC_WIDTH-1] && (|acc_reg[ACC_WIDTH-2 : FRAC_BITS + DATA_WIDTH - 1])) begin
            overflow  = 1'b1;
            underflow = 1'b0;
        end else if (acc_reg[ACC_WIDTH-1] && (!(&acc_reg[ACC_WIDTH-2 : FRAC_BITS + DATA_WIDTH - 1]))) begin
            overflow  = 1'b0;
            underflow = 1'b1;
        end else begin
            overflow  = 1'b0;
            underflow = 1'b0;
        end

        // Apply saturation logic
        if (overflow) begin
            out = {1'b0, {(DATA_WIDTH-1){1'b1}}}; // Maximum positive
        end else if (underflow) begin
            out = {1'b1, {(DATA_WIDTH-1){1'b0}}}; // Maximum negative
        end else begin
            out = truncated_out;
        end
    end

endmodule
