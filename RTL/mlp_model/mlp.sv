import mlp_weights_pkg::*;

module mlp (
    input  logic clk,
    input  logic signed [23:0] features [N_IN],
    output logic signed [23:0] logits [N_OUT],
    output logic [1:0] class_idx
);

    logic signed [23:0] h0 [N_H0];
    logic signed [23:0] h1 [N_H1];

    // ---------------- layer 0 : 132 -> 8, ReLU ---------------
    // features[0 .. N_BINS-1]  : |rFFT| da banda baixa depois do LMS (com sinal)
    // features[N_BINS .. N_IN-1]: agregados do quadro, ja deslocados de
    //                            EXTRA_SHIFT bits por quem monta o vetor
    genvar i;
    generate
        for (i = 0; i < N_H0; i++) begin : layer0
            perceptron #(
                .NUM_INPUTS(N_IN), .DATA_WIDTH(24), .WEIGHT_WIDTH(W_WIDTH),
                .RELU(1),
                .WEIGHTS(L0_W[i]), .BIAS(L0_B[i]), .SCALE(L0_SCALE[i])
            ) u_n (.inputs(features), .out(h0[i]));
        end
    endgenerate

    // ---------------- layer 1 : 8 -> 4, ReLU -----------------
    genvar j;
    generate
        for (j = 0; j < N_H1; j++) begin : layer1
            perceptron #(
                .NUM_INPUTS(N_H0), .DATA_WIDTH(24), .WEIGHT_WIDTH(W_WIDTH),
                .RELU(1),
                .WEIGHTS(L1_W[j]), .BIAS(L1_B[j]), .SCALE(L1_SCALE[j])
            ) u_n (.inputs(h0), .out(h1[j]));
        end
    endgenerate

    // ---------------- layer 2 : 4 -> 4, linear ---------------
    genvar k;
    generate
        for (k = 0; k < N_OUT; k++) begin : layer2
            perceptron #(
                .NUM_INPUTS(N_H1), .DATA_WIDTH(24), .WEIGHT_WIDTH(W_WIDTH),
                .RELU(0),
                .WEIGHTS(L2_W[k]), .BIAS(L2_B[k]), .SCALE(L2_SCALE[k])
            ) u_n (.inputs(h1), .out(logits[k]));
        end
    endgenerate

    // ---------------- argmax ---------------------------------
    always_comb begin
        logic signed [23:0] best;
        best      = logits[0];
        class_idx = 2'd0;
        for (int c = 1; c < N_OUT; c++)
            if (logits[c] > best) begin
                best      = logits[c];
                class_idx = c[1:0];
            end
    end

endmodule