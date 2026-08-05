`timescale 1ns / 1ps

module mac_q8_16 (
    input  logic               clk,
    input  logic               rst,
    input  logic               en,
    input  logic               clr, // Clears the accumulator
    input  logic signed [23:0] a,
    input  logic signed [23:0] b,
    output logic signed [23:0] out
);

    // Pipeline registers to ensure proper DSP48 inference (3 stages)
    logic signed [23:0] a_reg;
    logic signed [23:0] b_reg;
    logic               clr_reg1;
    logic               clr_reg2;
    (* multstyle = "dsp" *) logic signed [47:0] mult_reg;
    logic signed [47:0] acc_reg;

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

    // Combinational logic for safely extracting the Q8.16 result
    // from the Q16.32 accumulator, applying saturation.
    logic signed [23:0] truncated_out;
    logic overflow;
    logic underflow;

    always_comb begin
        truncated_out = acc_reg[39:16];
        
        // Overflow detection: 
        // If the number is positive (acc_reg[47] == 0), all upper bits [46:39] must be 0.
        // If the number is negative (acc_reg[47] == 1), all upper bits [46:39] must be 1.
        if (!acc_reg[47] && (|acc_reg[46:39])) begin
            overflow  = 1'b1;
            underflow = 1'b0;
        end else if (acc_reg[47] && (!(&acc_reg[46:39]))) begin
            overflow  = 1'b0;
            underflow = 1'b1;
        end else begin
            overflow  = 1'b0;
            underflow = 1'b0;
        end

        // Apply saturation logic
        if (overflow) begin
            out = 24'h7F_FFFF; // Maximum positive Q8.16
        end else if (underflow) begin
            out = 24'h80_0000; // Maximum negative Q8.16
        end else begin
            out = truncated_out;
        end
    end

endmodule
