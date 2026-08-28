// ---------------------------------------------------------------------
//  mac_seq_item  --  one whole dot-product job for the mac agent: taps
//                     0..n_taps-1 driven load-then-en as in mac_tb.sv's
//                     run_dot task. Since `load` on tap 0 always resets
//                     the accumulator, one item is fully self-contained
//                     -- there is no cross-item state for the scoreboard
//                     to track.
//
//  `data`/`weight` are randomized by sequences (or filled in directly by
//  directed sequences) and driven onto the DUT by the driver. `acc` is
//  not randomized: the monitor fills it in once the job settles, and
//  that's the copy the scoreboard checks against its golden model.
// ---------------------------------------------------------------------
class mac_seq_item #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_sequence_item;

    rand int unsigned n_taps;
    rand logic signed [DATA_WIDTH-1:0]   data   [];
    rand logic signed [WEIGHT_WIDTH-1:0] weight [];
         logic signed [SUM_WIDTH-1:0]    acc;        // filled in by the monitor

    constraint c_n_taps { n_taps inside {[1:MAX_TAPS]}; }
    constraint c_sizes  { data.size() == n_taps; weight.size() == n_taps; }

    `uvm_object_param_utils(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    function new(string name = "mac_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("n_taps=%0d acc=%0d | data=[", n_taps, acc);
        foreach (data[i])
            s = {s, $sformatf("%0d%s", data[i], (i == data.size()-1) ? "" : ",")};
        s = {s, "] weight=["};
        foreach (weight[i])
            s = {s, $sformatf("%0d%s", weight[i], (i == weight.size()-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to mac_seq_item failed")
        super.do_copy(rhs);
        n_taps = rhs_.n_taps;
        data   = rhs_.data;
        weight = rhs_.weight;
        acc    = rhs_.acc;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (n_taps == rhs_.n_taps) && (data == rhs_.data) &&
               (weight == rhs_.weight) && (acc == rhs_.acc);
    endfunction

endclass
