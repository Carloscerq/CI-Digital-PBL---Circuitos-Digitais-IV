import mlp_weights_pkg::*;

// Time-multiplexed MLP: 132 -> 8 -> 4 -> 4.
//
// The fully parallel version instantiated one `perceptron` per neuron, i.e.
// 8*132 + 4*8 + 4*4 = 1104 concurrent multipliers, which needs ~165% of the
// ALMs on a 5CEBA4 and saturates all 66 DSP blocks. Here N_MAC = 8 MAC units
// are reused across the three layers, so the whole network costs 8 DSP blocks
// for the dot products plus one shared scaler.
//
// Handshake: pulse `start`, keep `features` stable until `done` rises. `logits`
// and `class_idx` hold their value until the next `start`.
//
//   layer 0: 132 taps + 8 scale cycles
//   layer 1:   8 taps + 4 scale cycles
//   layer 2:   4 taps + 4 scale cycles      -> ~165 cycles per inference
module mlp (
    input  logic clk,
    input  logic rst_n,
    input  logic start,

    input  logic signed [ACC_WIDTH-1:0] features [N_IN],

    output logic signed [ACC_WIDTH-1:0] logits   [N_OUT],
    output logic [1:0] class_idx,
    output logic busy,
    output logic done
);

    // ACC_WIDTH (24) comes from the package and is the activation / bias /
    // scale width; SUM_WIDTH is the MAC accumulator, sized for the widest
    // layer (24 + 8 + clog2(132) = 40).
    localparam int ACT_WIDTH  = ACC_WIDTH;
    localparam int SUM_WIDTH  = ACT_WIDTH + W_WIDTH + $clog2(N_IN);
    localparam int PROD_WIDTH = SUM_WIDTH + ACT_WIDTH;

    localparam int N_MAC   = N_H0;              // widest layer sets the MAC count
    localparam int IDX_W   = $clog2(N_IN);
    localparam int NSEL_W  = $clog2(N_MAC);

    localparam logic signed [PROD_WIDTH-1:0] SAT_HI =  (1 <<< (ACT_WIDTH-1)) - 1;
    localparam logic signed [PROD_WIDTH-1:0] SAT_LO = -(1 <<< (ACT_WIDTH-1));

    // ---------------- scale + bias + activation ----------------------------
    // Identical arithmetic to perceptron.sv: the accumulator is scaled, shifted
    // down by Q_FRAC, biased, then ReLU'd *before* saturation. mlp_ref.cpp
    // relies on that order, so do not reorder the branches.
    function automatic logic signed [ACT_WIDTH-1:0] scale_sat (
        input logic signed [SUM_WIDTH-1:0] sum,
        input logic signed [ACT_WIDTH-1:0] scale,
        input logic signed [ACT_WIDTH-1:0] bias,
        input logic                        relu
    );
        logic signed [PROD_WIDTH-1:0] acc;
        acc = ((PROD_WIDTH'(sum) * scale) >>> Q_FRAC) + PROD_WIDTH'(bias);

        if (relu && acc < 0)   return '0;
        else if (acc > SAT_HI) return SAT_HI[ACT_WIDTH-1:0];
        else if (acc < SAT_LO) return SAT_LO[ACT_WIDTH-1:0];
        else                   return acc[ACT_WIDTH-1:0];
    endfunction

    // ---------------- control ----------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_ACC,      // stream taps into the MACs
        S_FLUSH,    // one cycle for the last fetched pair to land in the MACs
        S_SCALE,    // scale/bias/activate one neuron per cycle
        S_DONE
    } state_t;

    state_t state;
    logic [1:0]        layer;
    logic [IDX_W-1:0]  idx;      // tap index inside the current layer
    logic [NSEL_W-1:0] nsel;     // neuron being scaled

    // taps and neurons per layer
    logic [IDX_W-1:0]  n_taps;
    logic [NSEL_W-1:0] n_neurons;
    always_comb begin
        unique case (layer)
            2'd0:    begin n_taps = IDX_W'(N_IN);  n_neurons = NSEL_W'(N_H0);  end
            2'd1:    begin n_taps = IDX_W'(N_H0);  n_neurons = NSEL_W'(N_H1);  end
            default: begin n_taps = IDX_W'(N_H1);  n_neurons = NSEL_W'(N_OUT); end
        endcase
    end

    // ---------------- activations ------------------------------------------
    logic signed [ACT_WIDTH-1:0] h0 [N_H0];
    logic signed [ACT_WIDTH-1:0] h1 [N_H1];

    // ---------------- fetch stage ------------------------------------------
    // Weights and activations are read one cycle ahead of the multiply so the
    // weight arrays can be inferred as ROM instead of a combinational mux cone.
    logic signed [ACT_WIDTH-1:0] x;
    logic signed [W_WIDTH-1:0]   w [N_MAC];

    always_comb begin
        unique case (layer)
            2'd0:    x = features[idx];
            2'd1:    x = h0[idx[NSEL_W-1:0]];
            default: x = h1[idx[1:0]];
        endcase
    end

    always_comb begin
        for (int n = 0; n < N_MAC; n++) begin
            unique case (layer)
                2'd0:    w[n] = L0_W[n][idx];
                2'd1:    w[n] = (n < N_H1)  ? L1_W[n][idx[NSEL_W-1:0]] : '0;
                default: w[n] = (n < N_OUT) ? L2_W[n][idx[1:0]]        : '0;
            endcase
        end
    end

    // fetch/multiply pipeline registers
    logic signed [ACT_WIDTH-1:0] x_q;
    logic signed [W_WIDTH-1:0]   w_q  [N_MAC];
    logic                        en_q;
    logic                        load_q;

    // ---------------- MAC array --------------------------------------------
    logic signed [SUM_WIDTH-1:0] mac_acc [N_MAC];

    genvar g;
    generate
        for (g = 0; g < N_MAC; g++) begin : g_mac
            mac #(
                .DATA_WIDTH(ACT_WIDTH), .WEIGHT_WIDTH(W_WIDTH), .SUM_WIDTH(SUM_WIDTH)
            ) u_mac (
                .clk    (clk),
                .rst_n  (rst_n),
                .load   (load_q),
                .en     (en_q),
                .data   (x_q),
                .weight (w_q[g]),
                .acc    (mac_acc[g])
            );
        end
    endgenerate

    // ---------------- shared scaler ----------------------------------------
    // One scale multiplier for the whole network: the MACs of a layer finish
    // together and are then drained one neuron per cycle.
    logic signed [ACT_WIDTH-1:0] sc, bi;
    logic                        relu;
    always_comb begin
        unique case (layer)
            2'd0:    begin sc = L0_SCALE[nsel];      bi = L0_B[nsel];      relu = 1'b1; end
            2'd1:    begin sc = L1_SCALE[nsel[1:0]]; bi = L1_B[nsel[1:0]]; relu = 1'b1; end
            default: begin sc = L2_SCALE[nsel[1:0]]; bi = L2_B[nsel[1:0]]; relu = 1'b0; end
        endcase
    end

    logic signed [ACT_WIDTH-1:0] act;
    always_comb act = scale_sat(mac_acc[nsel], sc, bi, relu);

    // ---------------- argmax -----------------------------------------------
    // strict >, so the lowest index wins a tie -- matches argmax_first() in
    // mlp_ref.cpp
    logic [1:0] class_next;
    always_comb begin
        logic signed [ACT_WIDTH-1:0] best;
        best       = logits[0];
        class_next = 2'd0;
        for (int c = 1; c < N_OUT; c++)
            if (logits[c] > best) begin
                best       = logits[c];
                class_next = c[1:0];
            end
    end

    // ---------------- sequencer --------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            layer     <= 2'd0;
            idx       <= '0;
            nsel      <= '0;
            en_q      <= 1'b0;
            load_q    <= 1'b0;
            x_q       <= '0;
            busy      <= 1'b0;
            done      <= 1'b0;
            class_idx <= 2'd0;
            foreach (w_q[n])    w_q[n]    <= '0;
            foreach (h0[n])     h0[n]     <= '0;
            foreach (h1[n])     h1[n]     <= '0;
            foreach (logits[n]) logits[n] <= '0;
        end else begin
            // fetch stage defaults: nothing enters the MACs unless S_ACC says so
            en_q   <= 1'b0;
            load_q <= 1'b0;

            unique case (state)
                S_IDLE: begin
                    if (start) begin
                        state <= S_ACC;
                        layer <= 2'd0;
                        idx   <= '0;
                        busy  <= 1'b1;
                        done  <= 1'b0;
                    end
                end

                S_ACC: begin
                    // register the pair addressed by `idx` for the MACs to
                    // consume on the next edge
                    x_q    <= x;
                    foreach (w_q[n]) w_q[n] <= w[n];
                    en_q   <= 1'b1;
                    load_q <= (idx == '0);

                    if (idx == n_taps - 1'b1) begin
                        state <= S_FLUSH;
                        idx   <= '0;
                    end else begin
                        idx <= idx + 1'b1;
                    end
                end

                S_FLUSH: begin
                    // the last (x_q, w_q) pair accumulates on this edge
                    state <= S_SCALE;
                    nsel  <= '0;
                end

                S_SCALE: begin
                    unique case (layer)
                        2'd0:    h0[nsel]            <= act;
                        2'd1:    h1[nsel[1:0]]       <= act;
                        default: logits[nsel[1:0]]   <= act;
                    endcase

                    if (nsel == n_neurons - 1'b1) begin
                        if (layer == 2'd2) begin
                            state <= S_DONE;
                        end else begin
                            state <= S_ACC;
                            layer <= layer + 1'b1;
                            idx   <= '0;
                        end
                    end else begin
                        nsel <= nsel + 1'b1;
                    end
                end

                S_DONE: begin
                    // logits are settled now, so the argmax cone is valid
                    class_idx <= class_next;
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
