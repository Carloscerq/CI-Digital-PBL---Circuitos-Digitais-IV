// ---------------------------------------------------------------------
//  conv2d_fsm_scoreboard  --  independently recomputes, bit-exactly,
//  what every one of the CHANNELS output neurons should be for every
//  window, using the SAME real trained weight/bias .mem files the DUT
//  itself loads (see build_phase below) -- unlike tb_conv2d_fsm.sv,
//  which only ever checks liveness (output count + m_last timing) and
//  never the actual convolution math. This is the coverage gap this
//  testbench closes.
//
//  Golden model per neuron (mirrors conv2d_fsm.sv + mac_q8_16.sv
//  exactly):
//    acc_raw = sum_{k=0..IN_CHANNELS*9-1} window_flat[k] * weight[n][k]
//              + bias[n] * (1 <<< FRAC_BITS)
//  computed with unbounded (64-bit longint) precision -- individual
//  terms are at most ~2^47 in magnitude and there are only 37 of them,
//  so a 64-bit accumulation never itself overflows -- then truncated to
//  the accumulator's real ACC_W=48-bit width (acc_raw[ACC_W-1:0]) to
//  reproduce the hardware's 48-bit register wraparound bit-exactly
//  (modular addition is associative, so reducing once at the end gives
//  the same residue as the RTL's running 48-bit register would).
//  mac_q8_16's own truncate+saturate is then applied to that 48-bit
//  value using the exact same bit ranges as mac_q8_16.sv, and finally
//  conv2d_fsm's own sign-bit ReLU (`mac_out[DATA_WIDTH-1]==1 ? 0 :
//  mac_out`) -- not a numeric "<0" compare -- matching conv2d_fsm.sv's
//  generate block exactly.
//
//  window_flat[] uses the identical channel-major/row-major flattening
//  conv2d_fsm.sv's own `captured_window` uses, and weight[n][k] =
//  weights_flat[(n*IN_CHANNELS*9)+k], the identical flat indexing
//  conv2d_fsm.sv's `weight_idx` uses -- so weight index k lines up
//  exactly with window_flat[k] for every neuron.
//
//  Extends uvm_subscriber (like mlp_scoreboard) rather than declaring
//  its own uvm_analysis_imp_decl'd export: there is exactly one item
//  stream in (completed items from the monitor, one per output beat),
//  so the built-in analysis_export is all that's needed.
//
//  Covergroup bins: cp_relu splits windows into "some neuron got
//  ReLU-clamped to zero" vs "every neuron came out non-negative";
//  cp_sat splits windows into "some neuron's accumulator saturated"
//  vs "no neuron saturated" -- both sampled once per window from
//  flags declared ahead of the covergroup (a bare bit sampled by
//  reference, not `edge`/other reserved words, per the lessons from
//  the sibling agents' earlier mistakes on this effort).
// ---------------------------------------------------------------------
class conv2d_fsm_scoreboard extends uvm_subscriber #(conv2d_fsm_seq_item);

    `uvm_component_utils(conv2d_fsm_scoreboard)

    localparam int ACC_W = DATA_WIDTH * 2; // 48

    // Real trained weights/biases, loaded the same way conv2d_fsm.sv
    // loads them -- same CWD=RTL/ requirement (see run_uvm.sh).
    logic signed [DATA_WIDTH-1:0] weights_flat [0:(CHANNELS * IN_CHANNELS * 9)-1];
    logic signed [DATA_WIDTH-1:0] biases       [0:CHANNELS-1];

    int unsigned n_windows;
    int unsigned n_mismatch_windows;
    int unsigned n_mismatch_elems;
    int unsigned n_relu_clamped;
    int unsigned n_all_positive;
    int unsigned n_saturated;
    int unsigned n_not_saturated;

    // Sampled once per window; must be declared ahead of the covergroup
    // that references them.
    bit relu_sample;
    bit sat_sample;

    covergroup result_cg;
        option.per_instance = 1;
        cp_relu: coverpoint relu_sample {
            bins clamped      = {1};
            bins all_positive = {0};
        }
        cp_sat: coverpoint sat_sample {
            bins saturated     = {1};
            bins not_saturated = {0};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        // Same relative paths, same CWD=RTL/ requirement as
        // conv2d_fsm.sv's own $readmemh calls.
        $readmemh("mem/cnn/conv2d_weights.mem", weights_flat);
        $readmemh("mem/cnn/conv2d_biases.mem", biases);
        `uvm_info("SCOREBOARD", "loaded conv2d weights/biases from mem/cnn/*.mem", UVM_LOW)
    endfunction

    // --- mac_q8_16's exact truncate+saturate, plus conv2d_fsm's own
    //     sign-bit ReLU, applied to one neuron's golden accumulation ---
    function automatic void compute_neuron(
        input  logic signed [DATA_WIDTH-1:0] window_flat [0:(IN_CHANNELS*9)-1],
        input  int                           neuron,
        output logic signed [DATA_WIDTH-1:0] relu_out,
        output bit                           sat_hit,
        output bit                           clamp_hit
    );
        longint acc_raw;
        logic signed [ACC_W-1:0]      acc_w;
        logic signed [DATA_WIDTH-1:0] truncated_out;
        logic signed [DATA_WIDTH-1:0] mac_out;
        bit overflow, underflow;

        acc_raw = 64'sd0;
        for (int k = 0; k < IN_CHANNELS * 9; k++) begin
            acc_raw += longint'(window_flat[k]) *
                       longint'(weights_flat[(neuron * IN_CHANNELS * 9) + k]);
        end
        acc_raw += longint'(biases[neuron]) * (longint'(1) <<< FRAC_BITS);

        acc_w = acc_raw[ACC_W-1:0]; // reproduce the 48-bit register's wraparound

        truncated_out = acc_w[FRAC_BITS + DATA_WIDTH - 1 : FRAC_BITS];

        overflow  = 1'b0;
        underflow = 1'b0;
        if (!acc_w[ACC_W-1] && (|acc_w[ACC_W-2 : FRAC_BITS + DATA_WIDTH - 1])) begin
            overflow = 1'b1;
        end else if (acc_w[ACC_W-1] && (!(&acc_w[ACC_W-2 : FRAC_BITS + DATA_WIDTH - 1]))) begin
            underflow = 1'b1;
        end

        if (overflow) begin
            mac_out = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        end else if (underflow) begin
            mac_out = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        end else begin
            mac_out = truncated_out;
        end

        sat_hit   = overflow | underflow;
        clamp_hit = mac_out[DATA_WIDTH-1];
        relu_out  = clamp_hit ? '0 : mac_out;
    endfunction

    function void write(conv2d_fsm_seq_item t);
        logic signed [DATA_WIDTH-1:0] window_flat [0:(IN_CHANNELS*9)-1];
        logic signed [DATA_WIDTH-1:0] expected;
        bit sat, clamp;
        bit win_ok, win_sat, win_clamp;

        for (int ch = 0; ch < IN_CHANNELS; ch++) begin
            window_flat[(ch*9) + 0] = t.window[ch][0][0];
            window_flat[(ch*9) + 1] = t.window[ch][0][1];
            window_flat[(ch*9) + 2] = t.window[ch][0][2];
            window_flat[(ch*9) + 3] = t.window[ch][1][0];
            window_flat[(ch*9) + 4] = t.window[ch][1][1];
            window_flat[(ch*9) + 5] = t.window[ch][1][2];
            window_flat[(ch*9) + 6] = t.window[ch][2][0];
            window_flat[(ch*9) + 7] = t.window[ch][2][1];
            window_flat[(ch*9) + 8] = t.window[ch][2][2];
        end

        win_ok    = 1'b1;
        win_sat   = 1'b0;
        win_clamp = 1'b0;

        for (int n = 0; n < CHANNELS; n++) begin
            compute_neuron(window_flat, n, expected, sat, clamp);
            if (sat)   win_sat   = 1'b1;
            if (clamp) win_clamp = 1'b1;

            if (t.data_out[n] !== expected) begin
                win_ok = 1'b0;
                n_mismatch_elems++;
                `uvm_error("NEURON",
                    $sformatf("window %0d neuron %0d: expected %0h, got %0h",
                              n_windows, n, expected, t.data_out[n]))
            end
        end

        if (!win_ok) n_mismatch_windows++;

        relu_sample = win_clamp;
        sat_sample  = win_sat;
        result_cg.sample();

        if (win_clamp) n_relu_clamped++;   else n_all_positive++;
        if (win_sat)   n_saturated++;      else n_not_saturated++;

        n_windows++;
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("windows=%0d mismatched_windows=%0d mismatched_neurons=%0d",
                      n_windows, n_mismatch_windows, n_mismatch_elems), UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("relu_clamped=%0d all_positive=%0d saturated=%0d not_saturated=%0d coverage=%0.1f%%",
                      n_relu_clamped, n_all_positive, n_saturated, n_not_saturated,
                      result_cg.get_coverage()), UVM_LOW)

        if (n_windows == 0)
            `uvm_error("SCOREBOARD", "no windows were observed")

        if (n_mismatch_windows != 0)
            `uvm_error("SCOREBOARD",
                $sformatf("%0d of %0d windows mismatched the golden convolution model",
                          n_mismatch_windows, n_windows))
    endfunction

endclass
