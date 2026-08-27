`timescale 1ns/1ps

// Janela Hann de 64 pontos. A entrada inclui o bit de guarda criado pela
// remocao da media; a saida volta para DATA_WIDTH com arredondamento e
// saturacao. Os coeficientes permanecem Q1.17.
module hann_window_64_dualmode #(
    parameter integer INPUT_WIDTH       = 25,
    parameter integer COEFF_WIDTH       = 18,
    parameter integer OUTPUT_WIDTH      = 24,
    parameter integer COEFF_FRAC_BITS   = 17,
    parameter         INIT_FILE         =
        "../coefficients/windowing/hann_64_q117.bin"
)(
    input  wire                            clk,
    input  wire                            reset,
    input  wire signed [INPUT_WIDTH-1:0]   sample_in,
    input  wire                            sample_valid,
    output wire                            sample_ready,
    input  wire [5:0]                      sample_index,
    input  wire                            sample_first,
    input  wire                            sample_last,
    output reg signed [OUTPUT_WIDTH-1:0]   windowed_sample_out,
    output reg                             windowed_sample_valid,
    input  wire                            windowed_sample_ready,
    output reg [5:0]                       windowed_sample_index,
    output reg                             windowed_sample_first,
    output reg                             windowed_sample_last,
    output reg                             windowed_sample_saturated
);

    localparam integer PRODUCT_WIDTH = INPUT_WIDTH + COEFF_WIDTH;

    (* romstyle = "logic" *)
    reg signed [COEFF_WIDTH-1:0] hann_coefficients [0:63];
    wire signed [COEFF_WIDTH-1:0] coefficient;
    wire signed [PRODUCT_WIDTH-1:0] product;
    integer i;
    // synthesis translate_off
    integer coefficient_file;
    // synthesis translate_on

    assign coefficient = hann_coefficients[sample_index];
    assign product = $signed(sample_in) * $signed(coefficient);
    assign sample_ready =
        !windowed_sample_valid || windowed_sample_ready;

    function automatic signed [OUTPUT_WIDTH-1:0] round_and_saturate;
        input signed [PRODUCT_WIDTH-1:0] value;
        reg signed [63:0] value_wide;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_value;
        reg signed [63:0] rounding_constant;
        reg signed [63:0] maximum_value;
        reg signed [63:0] minimum_value;
        begin
            value_wide = value;
            rounding_constant = 64'sd1 <<< (COEFF_FRAC_BITS - 1);
            maximum_value = (64'sd1 <<< (OUTPUT_WIDTH - 1)) - 1;
            minimum_value = -(64'sd1 <<< (OUTPUT_WIDTH - 1));

            if (value_wide >= 0)
                rounded_value =
                    (value_wide + rounding_constant) >>> COEFF_FRAC_BITS;
            else begin
                magnitude = -value_wide;
                rounded_value =
                    -((magnitude + rounding_constant) >>> COEFF_FRAC_BITS);
            end

            if (rounded_value > maximum_value)
                round_and_saturate = {1'b0, {(OUTPUT_WIDTH-1){1'b1}}};
            else if (rounded_value < minimum_value)
                round_and_saturate = {1'b1, {(OUTPUT_WIDTH-1){1'b0}}};
            else
                round_and_saturate = rounded_value[OUTPUT_WIDTH-1:0];
        end
    endfunction

    function automatic rounding_saturates;
        input signed [PRODUCT_WIDTH-1:0] value;
        reg signed [63:0] value_wide;
        reg signed [63:0] magnitude;
        reg signed [63:0] rounded_value;
        reg signed [63:0] rounding_constant;
        reg signed [63:0] maximum_value;
        reg signed [63:0] minimum_value;
        begin
            value_wide = value;
            rounding_constant = 64'sd1 <<< (COEFF_FRAC_BITS - 1);
            maximum_value = (64'sd1 <<< (OUTPUT_WIDTH - 1)) - 1;
            minimum_value = -(64'sd1 <<< (OUTPUT_WIDTH - 1));

            if (value_wide >= 0)
                rounded_value =
                    (value_wide + rounding_constant) >>> COEFF_FRAC_BITS;
            else begin
                magnitude = -value_wide;
                rounded_value =
                    -((magnitude + rounding_constant) >>> COEFF_FRAC_BITS);
            end

            rounding_saturates =
                (rounded_value > maximum_value) ||
                (rounded_value < minimum_value);
        end
    endfunction

    initial begin
        for (i = 0; i < 64; i = i + 1)
            hann_coefficients[i] = {COEFF_WIDTH{1'b0}};

        // synthesis translate_off
        if (INIT_FILE == "")
            $fatal(1, "[hann_window_64_dualmode] INIT_FILE vazio.");

        coefficient_file = $fopen(INIT_FILE, "r");
        if (coefficient_file == 0)
            $fatal(1,
                "[hann_window_64_dualmode] Arquivo nao encontrado: %0s",
                INIT_FILE);

        $fclose(coefficient_file);
        // synthesis translate_on

        if (INIT_FILE != "")
            $readmemb(INIT_FILE, hann_coefficients);
    end

    always @(posedge clk) begin
        if (reset) begin
            windowed_sample_out       <= {OUTPUT_WIDTH{1'b0}};
            windowed_sample_valid     <= 1'b0;
            windowed_sample_index     <= 6'd0;
            windowed_sample_first     <= 1'b0;
            windowed_sample_last      <= 1'b0;
            windowed_sample_saturated <= 1'b0;
        end
        else if (sample_ready) begin
            windowed_sample_valid <= sample_valid;

            if (sample_valid) begin
                windowed_sample_out <= round_and_saturate(product);
                windowed_sample_index <= sample_index;
                windowed_sample_first <= sample_first;
                windowed_sample_last <= sample_last;
                windowed_sample_saturated <= rounding_saturates(product);
            end
            else
                windowed_sample_saturated <= 1'b0;
        end
    end

    // synthesis translate_off
    initial begin
        if (INPUT_WIDTH <= 1 || COEFF_WIDTH <= 1 || OUTPUT_WIDTH <= 1)
            $fatal(1,
                "[hann_window_64_dualmode] Largura invalida.");

        if (PRODUCT_WIDTH > 63)
            $fatal(1,
                "[hann_window_64_dualmode] PRODUCT_WIDTH deve ser <=63.");

        if (COEFF_WIDTH != 18 || COEFF_FRAC_BITS != 17)
            $fatal(1,
                "[hann_window_64_dualmode] Arquivo fornecido exige coeficientes Q1.17/18 bits.");
    end
    // synthesis translate_on

endmodule
