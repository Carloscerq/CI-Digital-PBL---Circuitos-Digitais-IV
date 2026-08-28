// ---------------------------------------------------------------------
//  mac_q8_16_seq_item  --  one whole job for the mac_q8_16 agent: taps
//                     0..n_taps-1 driven clr-then-en as in
//                     tb_mac_q8_16.sv's directed tests. Since `clr` on
//                     tap 0 always restarts the accumulator, one item is
//                     fully self-contained -- there is no cross-item
//                     state for the scoreboard to track.
//
//  `a`/`b` are randomized by sequences (or filled in directly by
//  directed sequences) and driven onto the DUT by the driver. `out` is
//  not randomized: the monitor fills it in once the job's pipeline has
//  drained, and that's the copy the scoreboard checks against its
//  golden model.
// ---------------------------------------------------------------------
class mac_q8_16_seq_item #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_sequence_item;

    rand int unsigned n_taps;
    rand logic signed [DATA_WIDTH-1:0] a [];
    rand logic signed [DATA_WIDTH-1:0] b [];
         logic signed [DATA_WIDTH-1:0] out;   // filled in by the monitor

    constraint c_n_taps { n_taps inside {[1:MAX_TAPS]}; }
    constraint c_sizes  { a.size() == n_taps; b.size() == n_taps; }

    `uvm_object_param_utils(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    function new(string name = "mac_q8_16_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("n_taps=%0d out=%0d | a=[", n_taps, out);
        foreach (a[i])
            s = {s, $sformatf("%0d%s", a[i], (i == a.size()-1) ? "" : ",")};
        s = {s, "] b=["};
        foreach (b[i])
            s = {s, $sformatf("%0d%s", b[i], (i == b.size()-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to mac_q8_16_seq_item failed")
        super.do_copy(rhs);
        n_taps = rhs_.n_taps;
        a      = rhs_.a;
        b      = rhs_.b;
        out    = rhs_.out;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (n_taps == rhs_.n_taps) && (a == rhs_.a) &&
               (b == rhs_.b) && (out == rhs_.out);
    endfunction

endclass
