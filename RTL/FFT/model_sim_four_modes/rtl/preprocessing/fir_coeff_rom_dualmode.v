`timescale 1ns/1ps

// ROM sincrona para coeficientes FIR signed Q1.17.
// Os coeficientes permanecem Q1.17 tanto no modo Q9.15 quanto no Q11.16.
module fir_coeff_rom_dualmode #(
    parameter integer COEFF_WIDTH = 18,
    parameter integer ADDR_WIDTH  = 7,
    parameter integer NUM_TAPS    = 47,
    parameter         INIT_FILE   =
        "model_sim_four_modes/coefficients/fir/stage1_decim4_q117.hex"
)(
    input  wire                          clk,
    input  wire                          reset,
    input  wire                          read_enable,
    input  wire [ADDR_WIDTH-1:0]         coeff_addr,
    output reg signed [COEFF_WIDTH-1:0]  coeff_out,
    output reg                           coeff_valid,
    output reg                           addr_error
);

    reg signed [COEFF_WIDTH-1:0] coeff_mem [0:NUM_TAPS-1];
    integer init_index;
`ifndef SYNTHESIS
    integer coefficient_file;
`endif

    initial begin
        for (init_index = 0; init_index < NUM_TAPS;
             init_index = init_index + 1)
            coeff_mem[init_index] = {COEFF_WIDTH{1'b0}};

`ifndef SYNTHESIS
        if (INIT_FILE == "")
            $fatal(1, "[fir_coeff_rom_dualmode] INIT_FILE vazio.");

        coefficient_file = $fopen(INIT_FILE, "r");
        if (coefficient_file == 0)
            $fatal(1,
                "[fir_coeff_rom_dualmode] Arquivo nao encontrado: %0s",
                INIT_FILE);
        $fclose(coefficient_file);
`endif

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, coeff_mem);
    end

    always @(posedge clk) begin
        if (reset) begin
            coeff_out   <= {COEFF_WIDTH{1'b0}};
            coeff_valid <= 1'b0;
            addr_error  <= 1'b0;
        end
        else begin
            coeff_valid <= 1'b0;
            addr_error  <= 1'b0;

            if (read_enable) begin
                if (coeff_addr < NUM_TAPS) begin
                    coeff_out   <= coeff_mem[coeff_addr];
                    coeff_valid <= 1'b1;
                end
                else begin
                    coeff_out   <= {COEFF_WIDTH{1'b0}};
                    addr_error  <= 1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (COEFF_WIDTH != 18)
            $warning(
                "[fir_coeff_rom_dualmode] COEFF_WIDTH=%0d; arquivos fornecidos usam Q1.17/18 bits.",
                COEFF_WIDTH);
        if (NUM_TAPS <= 0)
            $fatal(1, "[fir_coeff_rom_dualmode] NUM_TAPS invalido.");
        if ((1 << ADDR_WIDTH) < NUM_TAPS)
            $fatal(1,
                "[fir_coeff_rom_dualmode] ADDR_WIDTH nao representa NUM_TAPS.");
    end
`endif

endmodule
