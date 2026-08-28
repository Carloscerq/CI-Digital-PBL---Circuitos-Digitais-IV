// ---------------------------------------------------------------------
//  gcd_seq_item  --  one stimulus/response pair for the gcd agent.
//
//  `in` is randomized/assigned by sequences and driven onto the DUT by
//  the driver. `out` is not randomized: the monitor fills it in after
//  the `ready` pulse, and that's the copy the scoreboard checks.
// ---------------------------------------------------------------------
class gcd_seq_item #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_sequence_item;

    rand logic [SIZE-1:0] in [AMOUNT_OF_NUMBERS];
         logic [SIZE-1:0] out;

    `uvm_object_param_utils(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE))

    function new(string name = "gcd_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("out=%0d | in=[", out);
        foreach (in[i])
            s = {s, $sformatf("%0d%s", in[i], (i == AMOUNT_OF_NUMBERS-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to gcd_seq_item failed")
        super.do_copy(rhs);
        in  = rhs_.in;
        out = rhs_.out;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (in == rhs_.in) && (out == rhs_.out);
    endfunction

endclass
