module perceptron #(
    parameter int NUM_INPUTS   = 40,
    parameter int DATA_WIDTH   = 24,
    parameter int WEIGHT_WIDTH = 8,
    parameter int SCALE_WIDTH  = 24,
    parameter int Q_FRAC       = 15,
    parameter bit RELU         = 1,
    parameter logic signed [WEIGHT_WIDTH-1:0] WEIGHTS [NUM_INPUTS] = '{default: 0},
    parameter logic signed [DATA_WIDTH-1:0]   BIAS  = 0,
    parameter logic signed [SCALE_WIDTH-1:0]  SCALE = 0
)(
    input  logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS],
    output logic signed [DATA_WIDTH-1:0] out
);

    localparam int ACCUM_WIDTH = DATA_WIDTH + WEIGHT_WIDTH + $clog2(NUM_INPUTS);
    localparam int PROD_WIDTH  = ACCUM_WIDTH + SCALE_WIDTH;

    localparam logic signed [PROD_WIDTH-1:0] SAT_HI =  (1 <<< (DATA_WIDTH-1)) - 1;
    localparam logic signed [PROD_WIDTH-1:0] SAT_LO = -(1 <<< (DATA_WIDTH-1));

    logic signed [ACCUM_WIDTH-1:0] sum;
    logic signed [PROD_WIDTH-1:0]  acc;

    always_comb begin
        sum = '0;
        for (int i = 0; i < NUM_INPUTS; i++)
            sum = sum + (inputs[i] * WEIGHTS[i]);

        acc = ((PROD_WIDTH'(sum) * SCALE) >>> Q_FRAC) + PROD_WIDTH'(BIAS);
    end

    always_comb begin
        if (RELU && acc < 0)   out = '0;
        else if (acc > SAT_HI) out = SAT_HI[DATA_WIDTH-1:0];
        else if (acc < SAT_LO) out = SAT_LO[DATA_WIDTH-1:0];
        else                   out = acc[DATA_WIDTH-1:0];
    end

endmodule