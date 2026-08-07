`timescale 1ns / 1ps

module mac_q8_16 #(
    parameter int DATA_WIDTH = 24,
    parameter int FRAC_BITS = 16
)(
    input  logic               clk,
    input  logic               rst,
    input  logic               en,
    input  logic               clr, // Clears the accumulator
    input  logic signed [DATA_WIDTH-1:0] a,
    input  logic signed [DATA_WIDTH-1:0] b,
    output logic signed [DATA_WIDTH-1:0] out
);

    // Pipeline registers to ensure proper DSP48 inference (3 stages)
    logic signed [DATA_WIDTH-1:0] a_reg;
    logic signed [DATA_WIDTH-1:0] b_reg;
    logic               clr_reg1;
    logic               clr_reg2;
    (* multstyle = "dsp" *) logic signed [(DATA_WIDTH*2)-1:0] mult_reg;
    logic signed [(DATA_WIDTH*2)-1:0] acc_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
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
                acc_reg <= mult_reg;
            end else begin
                acc_reg <= acc_reg + mult_reg;
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
        // If the number is positive (acc_reg[(DATA_WIDTH*2)-1] == 0), all upper bits must be 0.
        // If the number is negative (acc_reg[(DATA_WIDTH*2)-1] == 1), all upper bits must be 1.
        if (!acc_reg[(DATA_WIDTH*2)-1] && (|acc_reg[(DATA_WIDTH*2)-2 : FRAC_BITS + DATA_WIDTH - 1])) begin
            overflow  = 1'b1;
            underflow = 1'b0;
        end else if (acc_reg[(DATA_WIDTH*2)-1] && (!(&acc_reg[(DATA_WIDTH*2)-2 : FRAC_BITS + DATA_WIDTH - 1]))) begin
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
