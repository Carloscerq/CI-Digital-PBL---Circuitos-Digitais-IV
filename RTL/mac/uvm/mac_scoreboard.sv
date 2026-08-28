// ---------------------------------------------------------------------
//  mac_scoreboard  --  self-checking golden model, ported from
//                       mac_tb.sv's run_dot task: 64-bit longint
//                       arithmetic, independent of the DUT's internal
//                       PROD_WIDTH, so a width bug in the DUT can't hide
//                       behind a matching bug in the checker.
//
//  MAC has no elaboration-time cfg (no weights/bias/scale to mirror the
//  way perceptron_scoreboard.sv does) -- everything the golden model
//  needs is inside the transaction itself.
//
//  Each accepted job is classified by tap-count bucket (a lone tap /
//  a short job / a mid-length job / a full MAX_TAPS job) and by whether
//  the raw 64-bit sum actually needed truncation to fit SUM_WIDTH bits,
//  and both axes are sampled onto a covergroup so the report shows what
//  the run actually exercised.
// ---------------------------------------------------------------------
typedef enum { TAP_1, TAP_SMALL, TAP_MID, TAP_MAX } mac_tap_bucket_e;

class mac_scoreboard #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_subscriber #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS));

    `uvm_component_param_utils(mac_scoreboard #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    mac_tap_bucket_e last_bucket;
    bit              last_saturated;

    covergroup result_cg;
        option.per_instance = 1;
        cp_bucket: coverpoint last_bucket {
            bins tap_1     = {TAP_1};
            bins tap_small = {TAP_SMALL};
            bins tap_mid   = {TAP_MID};
            bins tap_max   = {TAP_MAX};
        }
        cp_sat: coverpoint last_saturated {
            bins not_sat = {1'b0};
            bins sat     = {1'b1};
        }
        cross_bucket_sat: cross cp_bucket, cp_sat;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    // classifies a job's tap count into one of the four coverage buckets;
    // boundaries line up with the {1,2,4,8,33,MAX_TAPS} sweep mac_random_seq
    // (and mac_tb.sv's own `lengths` array) exercises
    function automatic mac_tap_bucket_e classify_taps(int unsigned n);
        if (n == 1)             return TAP_1;
        else if (n == MAX_TAPS) return TAP_MAX;
        else if (n <= 8)        return TAP_SMALL;
        else                    return TAP_MID;
    endfunction

    // truncates/sign-extends a 64-bit golden sum to SUM_WIDTH bits, the
    // same way the DUT's `SUM_WIDTH'(prod)` cast (and its running
    // accumulation) behaves. For the default 24/8/40 config this is a
    // no-op -- SUM_WIDTH already comfortably holds the MAX_TAPS=132
    // worst case (mac_tb.sv's SAT_MAX_POS/SAT_MAX_NEG checks) -- but it
    // keeps the comparison correct for any narrower SUM_WIDTH too.
    function automatic longint signed truncate(longint signed val);
        longint unsigned mask;
        longint signed   result;
        if (SUM_WIDTH >= 64) return val;
        mask   = (longint'(1) <<< SUM_WIDTH) - 1;
        result = longint'(longint'(val) & mask);
        if (result[SUM_WIDTH-1])
            result = result | ~mask;
        return result;
    endfunction

    function void write(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) t);
        longint signed sum, exp, got;

        sum = 0;
        foreach (t.data[i])
            sum += longint'(t.data[i]) * longint'(t.weight[i]);

        exp = truncate(sum);
        got = longint'(t.acc);

        last_bucket    = classify_taps(t.n_taps);
        last_saturated = (exp != sum);
        result_cg.sample();

        if (got !== exp) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("expected %0d got %0d (raw sum=%0d, n_taps=%0d) | %s",
                          exp, got, sum, t.n_taps, t.convert2string()))
        end else begin
            match_count++;
            `uvm_info("MATCH", $sformatf("expected == got == %0d (n_taps=%0d)", exp, t.n_taps), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("matches=%0d mismatches=%0d bucket*sat coverage=%0.1f%%",
                      match_count, mismatch_count, result_cg.get_coverage()),
            UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
