// ---------------------------------------------------------------------
//  euclidian_gcd_seq_item  --  one pairwise GCD job for the euclidian_gcd
//                               agent: a single (in_a, in_b) pair driven
//                               through the start/ready handshake, exactly
//                               like one call to validate() in
//                               euclidian_gcd_tb.sv.
//
//  `in_a`/`in_b` are randomized/assigned by sequences and driven onto the
//  DUT by the driver. `out` is not randomized: the monitor fills it in
//  once `ready` pulses, and that's the copy the scoreboard checks against
//  its golden model.
// ---------------------------------------------------------------------
class euclidian_gcd_seq_item #(
    int SIZE = 32
) extends uvm_sequence_item;

    rand logic [SIZE-1:0] in_a;
    rand logic [SIZE-1:0] in_b;
         logic [SIZE-1:0] out;    // filled in by the monitor

    `uvm_object_param_utils(euclidian_gcd_seq_item #(SIZE))

    function new(string name = "euclidian_gcd_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("in_a=%0d in_b=%0d out=%0d", in_a, in_b, out);
    endfunction

    function void do_copy(uvm_object rhs);
        euclidian_gcd_seq_item #(SIZE) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to euclidian_gcd_seq_item failed")
        super.do_copy(rhs);
        in_a = rhs_.in_a;
        in_b = rhs_.in_b;
        out  = rhs_.out;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        euclidian_gcd_seq_item #(SIZE) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (in_a == rhs_.in_a) && (in_b == rhs_.in_b) && (out == rhs_.out);
    endfunction

endclass
