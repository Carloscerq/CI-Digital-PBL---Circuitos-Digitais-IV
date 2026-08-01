module perceptron #(
    parameter int NUM_INPUTS = 2,
    parameter int DATA_WIDTH = 8,
    parameter logic signed [DATA_WIDTH-1:0] WEIGHTS [NUM_INPUTS] = '{8'sd1, 8'sd1},
    parameter logic signed [DATA_WIDTH-1:0] BIAS = 8'sd0
)(
    input  logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS],
    output logic out
);

    localparam int ACCUM_WIDTH = (2 * DATA_WIDTH) + $clog2(NUM_INPUTS);
    logic signed [ACCUM_WIDTH-1:0] sum;

    always_comb begin
        sum = BIAS;
        for (int i = 0; i < NUM_INPUTS; i++) begin
            sum = sum + (inputs[i] * WEIGHTS[i]);
        end
    end

    assign out = (sum > 0) ? 1'b1 : 1'b0;

endmodule