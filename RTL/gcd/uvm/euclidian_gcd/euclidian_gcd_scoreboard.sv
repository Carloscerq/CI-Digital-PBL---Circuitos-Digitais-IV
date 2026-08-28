// ---------------------------------------------------------------------
//  euclidian_gcd_scoreboard  --  self-checking golden model.
//
//  euclidian_gcd.sv computes GCD by repeated subtraction (binary/
//  Euclidean, subtraction-based): while CALC, `if (a>b) a-=b; else if
//  (b>a) b-=a; else b=0;` each cycle until either register hits 0, then
//  outputs whichever register is nonzero (or 0 if both are). That is
//  mathematically identical to what the standard mod-based Euclidean
//  algorithm converges to, so the golden model below reuses the exact
//  ref_gcd() implementation gcd_tb.sv (one directory up) already checks
//  its own array-reducer against, rather than reimplementing the
//  subtraction loop:
//
//    while (b != 0) begin tmp = b; b = a % b; a = tmp; end
//    return a;
//
//  This naturally reproduces the DUT's documented convention with no
//  special-casing needed: ref_gcd(0,0)=0 (loop body never runs, returns
//  a=0), ref_gcd(0,b)=b (one iteration: tmp=b, b=0%b=0, a=tmp=b, loop
//  exits, returns b), ref_gcd(a,0)=a (loop body never runs, returns
//  a=a) -- exactly the DUT's gcd(0,0)=0 / gcd(0,b)=b / gcd(a,0)=a.
//
//  Each accepted job is classified into one of five mutually exclusive
//  cases and sampled onto a covergroup so the report shows what the run
//  actually exercised: an operand being zero, equal nonzero operands,
//  a coprime result, or the general/normal case.
// ---------------------------------------------------------------------
typedef enum {
    CASE_A_ZERO,
    CASE_B_ZERO,
    CASE_EQUAL_NONZERO,
    CASE_COPRIME,
    CASE_NORMAL
} euclidian_gcd_case_e;

class euclidian_gcd_scoreboard #(
    int SIZE = 32
) extends uvm_subscriber #(euclidian_gcd_seq_item #(SIZE));

    `uvm_component_param_utils(euclidian_gcd_scoreboard #(SIZE))

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    euclidian_gcd_case_e last_case;

    covergroup result_cg;
        option.per_instance = 1;
        cp_case: coverpoint last_case {
            bins a_zero        = {CASE_A_ZERO};
            bins b_zero        = {CASE_B_ZERO};
            bins equal_nonzero = {CASE_EQUAL_NONZERO};
            bins coprime       = {CASE_COPRIME};
            bins normal        = {CASE_NORMAL};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    // behavioural reference, ported verbatim from gcd_tb.sv's ref_gcd()
    function automatic logic [SIZE-1:0] ref_gcd(
        input logic [SIZE-1:0] a,
        input logic [SIZE-1:0] b
    );
        logic [SIZE-1:0] tmp;
        begin
            while (b != 0) begin
                tmp = b;
                b   = a % b;
                a   = tmp;
            end
            return a;
        end
    endfunction

    // classifies a job into one of the five coverage cases; checked in
    // priority order so the classification stays mutually exclusive
    // (e.g. (0,0) lands on a_zero, not also b_zero)
    function automatic euclidian_gcd_case_e classify(
        input logic [SIZE-1:0] a,
        input logic [SIZE-1:0] b,
        input logic [SIZE-1:0] result
    );
        if (a == 0)           return CASE_A_ZERO;
        else if (b == 0)      return CASE_B_ZERO;
        else if (a == b)      return CASE_EQUAL_NONZERO;
        else if (result == 1) return CASE_COPRIME;
        else                  return CASE_NORMAL;
    endfunction

    function void write(euclidian_gcd_seq_item #(SIZE) t);
        logic [SIZE-1:0] expected;

        expected = ref_gcd(t.in_a, t.in_b);

        last_case = classify(t.in_a, t.in_b, t.out);
        result_cg.sample();

        if (t.out !== expected) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("in_a=%0d in_b=%0d: expected %0d got %0d",
                          t.in_a, t.in_b, expected, t.out))
        end else begin
            match_count++;
            `uvm_info("MATCH",
                $sformatf("in_a=%0d in_b=%0d gcd=%0d", t.in_a, t.in_b, t.out), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("matches=%0d mismatches=%0d case coverage=%0.1f%%",
                      match_count, mismatch_count, result_cg.get_coverage()),
            UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
