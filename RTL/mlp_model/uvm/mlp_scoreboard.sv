// ---------------------------------------------------------------------
//  mlp_scoreboard  --  wraps the same bit-exact C++ reference
//  (mlp_ref.cpp) that mlp_tb_dpi.sv checks against, via the DPI-C
//  imports declared at mlp_pkg scope (see mlp_pkg.sv). No SystemVerilog
//  reimplementation of the network's math lives here -- push the
//  transaction's features through ref_set_input/ref_run and compare
//  every logit plus class_idx, exactly like the original tb's checking
//  loop.
//
//  fixed-vs-float class disagreement is quantisation, not an RTL fault,
//  and is tracked separately (n_quant) rather than counted as a
//  mismatch -- same distinction the original tb draws.
//
//  hist[] and n_ties reproduce the two conditions the original tb warns
//  about at the end of the run (hist indexed by the *reference* class,
//  same as mlp_tb_dpi.sv's `hist[ref_class]++`):
//    - hist[2] == 0            -> class 2 ("None") was never predicted
//    - n_ties == 0             -> no vector tied for the max logit, so
//                                 the argmax tie-break is untested
//  The covergroup below samples the same two facts (predicted class,
//  tie-at-max) so the coverage report shows the same story; the
//  explicit counters are what report_phase() actually branches on,
//  since they're unambiguous without depending on per-bin covergroup
//  query syntax.
// ---------------------------------------------------------------------
class mlp_scoreboard extends uvm_subscriber #(mlp_seq_item);

    `uvm_component_utils(mlp_scoreboard)

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;
    int unsigned n_quant        = 0;
    int unsigned n_sat          = 0;
    int unsigned n_ties         = 0;
    int unsigned n_vectors      = 0;
    int unsigned hist [4]       = '{default: 0};

    logic [1:0] last_class;
    bit         last_tie;

    covergroup result_cg;
        option.per_instance = 1;
        cp_class: coverpoint last_class {
            bins bearing   = {0};
            bins misalign  = {1};
            bins none      = {2};
            bins unbalance = {3};
        }
        cp_tie: coverpoint last_tie {
            bins no_tie = {0};
            bins tie    = {1};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function string cname(input int c);
        case (c)
            0: return "Bearing";
            1: return "Misalign";
            2: return "None";
            3: return "Unbalance";
            default: return "?";
        endcase
    endfunction

    function void write(mlp_seq_item t);
        int ref_class, ref_float_class;
        logic signed [ACC_WIDTH-1:0] mx;
        int n_at_max;
        bit ok;

        n_vectors++;
        ok = 1'b1;

        for (int i = 0; i < N_IN; i++)
            ref_set_input(i, int'(t.features[i]));
        ref_run();

        ref_class       = ref_get_class();
        ref_float_class = ref_get_float_class();
        hist[ref_class]++;
        if (ref_get_saturated() != 0) n_sat++;

        // argmax tie-break (strict >, lowest index wins) is only exercised
        // when the *maximum* is shared by more than one logit
        mx = t.logits[0];
        for (int j = 1; j < N_OUT; j++) if (t.logits[j] > mx) mx = t.logits[j];
        n_at_max = 0;
        for (int j = 0; j < N_OUT; j++) if (t.logits[j] == mx) n_at_max++;
        last_tie = (n_at_max > 1);
        if (last_tie) n_ties++;

        for (int j = 0; j < N_OUT; j++)
            if (!(int'(t.logits[j]) === ref_get_logit(j))) begin
                ok = 1'b0;
                `uvm_error("LOGIT", $sformatf("vec %0d, logit %0d: reference %0d, RTL %0d",
                           n_vectors-1, j, ref_get_logit(j), int'(t.logits[j])))
            end

        if (!(int'(t.class_idx) === ref_class)) begin
            ok = 1'b0;
            `uvm_error("CLASS", $sformatf("vec %0d: reference %0d (%s), RTL %0d (%s)",
                       n_vectors-1, ref_class, cname(ref_class),
                       int'(t.class_idx), cname(int'(t.class_idx))))
        end

        last_class = 2'(ref_class);
        result_cg.sample();

        // fixed vs float disagreement is quantisation, not an RTL fault
        if (ref_class != ref_float_class) begin
            n_quant++;
            if (n_quant <= 10)
                `uvm_info("QUANT",
                    $sformatf("vec %0d fixed=%s float=%s (float logits %.3f %.3f %.3f %.3f)",
                              n_vectors-1, cname(ref_class), cname(ref_float_class),
                              ref_get_float_logit(0), ref_get_float_logit(1),
                              ref_get_float_logit(2), ref_get_float_logit(3)),
                    UVM_MEDIUM)
        end

        if (ok) match_count++;
        else    mismatch_count++;
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("vectors=%0d matches=%0d mismatches=%0d quant_notes=%0d saturating=%0d ties=%0d",
                      n_vectors, match_count, mismatch_count, n_quant, n_sat, n_ties), UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("predicted classes: %s=%0d %s=%0d %s=%0d %s=%0d",
                      cname(0), hist[0], cname(1), hist[1], cname(2), hist[2], cname(3), hist[3]),
            UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("class/tie covergroup: %0.1f%%", result_cg.get_coverage()), UVM_LOW)

        if (n_ties == 0)
            `uvm_info("SCOREBOARD",
                "NOTE: no vector tied for the maximum logit, so the argmax tie-break (strict >, lowest index wins) is untested.",
                UVM_LOW)

        if (hist[2] == 0)
            `uvm_warning("SCOREBOARD",
                "the 'None' class was never predicted -- random spectra cannot reach it. Feed real feature rows to cover it.")

        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
    endfunction

endclass
