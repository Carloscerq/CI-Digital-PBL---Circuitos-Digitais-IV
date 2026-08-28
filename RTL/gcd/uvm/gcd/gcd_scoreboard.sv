// ---------------------------------------------------------------------
//  gcd_scoreboard  --  self-checking golden model, ported from
//                       ref_gcd()/the folding loop in gcd_tb.sv: a plain
//                       Euclidean gcd(a,b) function, folded left-to-right
//                       over the array starting from in[0], using the
//                       same neutral-element convention euclidian_gcd.sv
//                       documents: gcd(0,0)=0, gcd(0,b)=b, gcd(a,0)=a.
//
//  This is mathematically equivalent to the DUT's chained
//  subtraction-based pairwise euclidian_gcd calls, early-exit
//  optimization included: gcd.sv's FSM stops scanning the array early
//  once the running gcd hits 1 (no later number can lower it), but that
//  only shortens the DUT's cycle count -- it never changes the final
//  folded result, so this golden model doesn't need to reproduce the
//  early exit itself to be exact.
//
//  The covergroup below mirrors the deliberate edge cases gcd_tb.sv's
//  directed vectors exercise: an all-zero input (result 0), a coprime
//  input where the DUT's early exit is likely exercised (result 1), and
//  the general/normal case.
// ---------------------------------------------------------------------
typedef enum { GCD_RES_ZERO, GCD_RES_ONE, GCD_RES_NORMAL } gcd_result_e;

class gcd_scoreboard #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_subscriber #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE));

    `uvm_component_param_utils(gcd_scoreboard #(AMOUNT_OF_NUMBERS, SIZE))

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    gcd_result_e last_bin;

    covergroup result_cg;
        option.per_instance = 1;
        cp_result: coverpoint last_bin {
            bins all_zero = {GCD_RES_ZERO};
            bins coprime  = {GCD_RES_ONE};
            bins normal   = {GCD_RES_NORMAL};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    // behavioural reference for a single pair, mirrors ref_gcd() in
    // gcd_tb.sv: gcd(0,0)=0, gcd(0,b)=b, gcd(a,0)=a
    function automatic logic [SIZE-1:0] pair_gcd(
        logic [SIZE-1:0] a,
        logic [SIZE-1:0] b
    );
        logic [SIZE-1:0] tmp;
        begin
            while (b != 0) begin
                tmp = b;
                b   = a % b;
                a   = tmp;
            end
            pair_gcd = a;
        end
    endfunction

    function void write(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) t);
        logic [SIZE-1:0] expected;

        expected = t.in[0];
        for (int i = 1; i < AMOUNT_OF_NUMBERS; i++)
            expected = pair_gcd(expected, t.in[i]);

        if (expected == 0)      last_bin = GCD_RES_ZERO;
        else if (expected == 1) last_bin = GCD_RES_ONE;
        else                    last_bin = GCD_RES_NORMAL;
        result_cg.sample();

        if (t.out !== expected) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("expected %0d got %0d | %s", expected, t.out, t.convert2string()))
        end else begin
            match_count++;
            `uvm_info("MATCH", $sformatf("expected == got == %0d", expected), UVM_HIGH)
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("matches=%0d mismatches=%0d result_coverage=%0.1f%%",
                      match_count, mismatch_count, result_cg.get_coverage()),
            UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
