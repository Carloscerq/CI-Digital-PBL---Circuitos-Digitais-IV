// ---------------------------------------------------------------------
//  mac_q8_16_scoreboard  --  self-checking golden model, a direct
//  transcription of mac_q8_16.sv's own always_comb block (truncated_out
//  / overflow / underflow / final saturating mux), operating on an
//  exact 64-bit longint sum rather than trusting the DUT's own internal
//  acc_reg -- so a width/saturation bug in the DUT can't hide behind a
//  matching bug in the checker.
//
//  mac_q8_16 has no elaboration-time cfg (no weights/bias to mirror the
//  way perceptron_scoreboard.sv does) -- everything the golden model
//  needs is inside the transaction itself.
//
//  A covergroup classifies each job's result as normal / overflow /
//  underflow so the report shows whether saturation was actually
//  exercised in both directions. `last_kind` (the coverpoint expression)
//  is declared before the covergroup that samples it -- Xcelium requires
//  the coverpoint's member to already be declared earlier in the class
//  body (a forward reference to a later member fails with *E,UNDIDN
//  even though some other tools accept it).
// ---------------------------------------------------------------------
typedef enum { RESULT_NORMAL, RESULT_OVERFLOW, RESULT_UNDERFLOW } mac_q8_16_result_kind_e;

class mac_q8_16_scoreboard #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_subscriber #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS));

    `uvm_component_param_utils(mac_q8_16_scoreboard #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    localparam int ACC_W = 2 * DATA_WIDTH;

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    mac_q8_16_result_kind_e last_kind;   // declared before the covergroup below, on purpose

    covergroup result_cg;
        option.per_instance = 1;
        cp_kind: coverpoint last_kind {
            bins normal      = {RESULT_NORMAL};
            bins overflow_hit  = {RESULT_OVERFLOW};
            bins underflow_hit = {RESULT_UNDERFLOW};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    // exact transcription of mac_q8_16.sv's always_comb: truncated_out /
    // overflow / underflow / saturating mux, operating on the exact
    // 64-bit sum instead of the DUT's own acc_reg.
    function automatic logic signed [DATA_WIDTH-1:0] golden_result(longint signed acc_raw, output bit overflow, output bit underflow);
        logic signed [ACC_W-1:0]      acc_w;
        logic signed [DATA_WIDTH-1:0] truncated_out;
        logic signed [DATA_WIDTH-1:0] result;

        // keep only the low ACC_W bits of the exact sum, mirroring the
        // real acc_reg's finite width (2's-complement truncation --
        // for the magnitudes these tests use this never actually wraps,
        // but the masking is implemented properly rather than assumed).
        acc_w = acc_raw[ACC_W-1:0];

        truncated_out = acc_w[FRAC_BITS + DATA_WIDTH - 1 : FRAC_BITS];

        if (!acc_w[ACC_W-1] && (|acc_w[ACC_W-2 : FRAC_BITS + DATA_WIDTH - 1])) begin
            overflow  = 1'b1;
            underflow = 1'b0;
        end else if (acc_w[ACC_W-1] && (!(&acc_w[ACC_W-2 : FRAC_BITS + DATA_WIDTH - 1]))) begin
            overflow  = 1'b0;
            underflow = 1'b1;
        end else begin
            overflow  = 1'b0;
            underflow = 1'b0;
        end

        if (overflow)
            result = {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else if (underflow)
            result = {1'b1, {(DATA_WIDTH-1){1'b0}}};
        else
            result = truncated_out;

        return result;
    endfunction

    function void write(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) t);
        longint signed acc_raw;
        logic signed [DATA_WIDTH-1:0] exp;
        logic signed [DATA_WIDTH-1:0] got;
        bit overflow, underflow;

        acc_raw = 0;
        foreach (t.a[i])
            acc_raw += longint'(t.a[i]) * longint'(t.b[i]);

        exp = golden_result(acc_raw, overflow, underflow);
        got = t.out;

        last_kind = overflow  ? RESULT_OVERFLOW :
                    underflow ? RESULT_UNDERFLOW :
                                RESULT_NORMAL;
        result_cg.sample();

        if (got !== exp) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("expected %0d got %0d (raw sum=%0d, n_taps=%0d) | %s",
                          exp, got, acc_raw, t.n_taps, t.convert2string()))
        end else begin
            match_count++;
            `uvm_info("MATCH", $sformatf("expected == got == %0d (n_taps=%0d)", exp, t.n_taps), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("matches=%0d mismatches=%0d result-kind coverage=%0.1f%%",
                      match_count, mismatch_count, result_cg.get_coverage()),
            UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
