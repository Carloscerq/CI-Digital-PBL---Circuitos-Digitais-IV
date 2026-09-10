module mac #(
    parameter int DATA_WIDTH   = 24,
    parameter int WEIGHT_WIDTH = 8,
    parameter int SUM_WIDTH    = 40   // must hold NUM_INPUTS * 2**(DW+WW-2)
)(
    input  logic clk,
    input  logic reset,

    input  logic load,                             // acc <= data*weight  (first tap)
    input  logic en,                               // acc <= acc + data*weight
    input  logic signed [DATA_WIDTH-1:0]   data,
    input  logic signed [WEIGHT_WIDTH-1:0] weight,

    output logic signed [SUM_WIDTH-1:0]    acc
);
    localparam int PROD_WIDTH = DATA_WIDTH + WEIGHT_WIDTH;

    logic signed [PROD_WIDTH-1:0] prod;
    always_comb prod = data * weight;

    always_ff @(posedge clk) begin
        if (reset)     acc <= '0;
        else if (load) acc <= SUM_WIDTH'(prod);
        else if (en)   acc <= acc + SUM_WIDTH'(prod);
    end

endmodule
