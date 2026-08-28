// ---------------------------------------------------------------------
//  perceptron_scoreboard  --  self-checking golden model, ported from
//                              the `golden()` function in
//                              perceptron_tb_fixedpoint.sv: 64-bit
//                              arithmetic, independent of the DUT's
//                              internal ACCUM_WIDTH/PROD_WIDTH, so a
//                              width bug in the DUT can't hide behind a
//                              matching bug in the checker.
//
//  Each accepted transaction is also classified into which branch of
//  perceptron.sv's output mux it should have taken (ReLU clamp,
//  saturate high/low, exact zero, normal pass-through) and sampled onto
//  a covergroup, so the report shows which of those branches the run
//  actually exercised.
//
//  Note: when RELU=1 the `acc < 0` check is evaluated before the
//  saturate-low check, so SAT_LO can never fire for a RELU-enabled DUT
//  instance -- that bin will read 0% by construction, not because
//  coverage is missing. A RELU=0 instance (see the "further work" note
//  in the uvm/ README) is what closes that bin.
// ---------------------------------------------------------------------
typedef enum { RELU_CLAMP, SAT_HI, SAT_LO, ZERO, NORMAL } perceptron_result_e;

class perceptron_scoreboard #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_subscriber #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH));

    `uvm_component_param_utils(perceptron_scoreboard #(NUM_INPUTS, DATA_WIDTH))

    perceptron_cfg cfg;

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    perceptron_result_e last_bin;

    covergroup result_cg;
        option.per_instance = 1;
        cp_result: coverpoint last_bin {
            bins relu_clamp = {RELU_CLAMP};
            bins sat_hi     = {SAT_HI};
            bins sat_lo     = {SAT_LO};
            bins zero       = {ZERO};
            bins normal     = {NORMAL};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(perceptron_cfg)::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "perceptron_cfg not set for scoreboard")
        if (cfg.weights.size() != NUM_INPUTS)
            `uvm_fatal("CFG", $sformatf("cfg.weights has %0d entries, expected NUM_INPUTS=%0d",
                                         cfg.weights.size(), NUM_INPUTS))
    endfunction

    // classifies and returns the expected output for a given weighted sum
    function automatic longint signed compute_golden(longint signed sum);
        longint signed acc, hi, lo;
        acc = ((sum * cfg.scale) >>> cfg.q_frac) + cfg.bias;
        hi  =  (longint'(1) <<< (cfg.data_width - 1)) - 1;
        lo  = -(longint'(1) <<< (cfg.data_width - 1));

        if (cfg.relu && acc < 0) begin
            last_bin = RELU_CLAMP;
            return 0;
        end else if (acc > hi) begin
            last_bin = SAT_HI;
            return hi;
        end else if (acc < lo) begin
            last_bin = SAT_LO;
            return lo;
        end else if (acc == 0) begin
            last_bin = ZERO;
            return acc;
        end else begin
            last_bin = NORMAL;
            return acc;
        end
    endfunction

    function void write(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) t);
        longint signed sum, exp, got;

        sum = 0;
        foreach (t.inputs[i])
            sum += longint'(t.inputs[i]) * cfg.weights[i];

        exp = compute_golden(sum);
        got = longint'(t.out);
        result_cg.sample();

        if (got !== exp) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("expected %0d got %0d (sum=%0d) | %s", exp, got, sum, t.convert2string()))
        end else begin
            match_count++;
            `uvm_info("MATCH", $sformatf("expected == got == %0d", exp), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("matches=%0d mismatches=%0d branch_coverage=%0.1f%%",
                      match_count, mismatch_count, result_cg.get_coverage()),
            UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
