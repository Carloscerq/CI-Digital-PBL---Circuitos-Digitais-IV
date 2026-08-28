// ---------------------------------------------------------------------
//  mlp_seq_item  --  one stimulus/response pair for the mlp agent.
//
//  `features` is randomized/assigned by sequences and driven onto the
//  DUT by the driver. `logits`/`class_idx` are not randomized: the
//  monitor fills them in after `done` rises, and that's the copy the
//  scoreboard checks. `latency_cycles` is the cycle count the monitor
//  measured from the `start` pulse to `done` -- informational only, not
//  checked against a fixed value since mlp's latency depends on which
//  branch of the sequencer state machine layer 1/2 take (it doesn't;
//  the network is fixed-schedule, but the field is here for visibility
//  and possible future latency assertions).
// ---------------------------------------------------------------------
class mlp_seq_item extends uvm_sequence_item;

    rand logic signed [ACC_WIDTH-1:0] features [N_IN];
         logic signed [ACC_WIDTH-1:0] logits   [N_OUT];
         logic [1:0]                  class_idx;
         int                          latency_cycles;

    `uvm_object_utils(mlp_seq_item)

    function new(string name = "mlp_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("class_idx=%0d latency=%0d | logits=[", class_idx, latency_cycles);
        foreach (logits[i])
            s = {s, $sformatf("%0d%s", logits[i], (i == N_OUT-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        mlp_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to mlp_seq_item failed")
        super.do_copy(rhs);
        features       = rhs_.features;
        logits         = rhs_.logits;
        class_idx      = rhs_.class_idx;
        latency_cycles = rhs_.latency_cycles;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        mlp_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (features == rhs_.features) && (logits == rhs_.logits) &&
               (class_idx == rhs_.class_idx);
    endfunction

endclass
