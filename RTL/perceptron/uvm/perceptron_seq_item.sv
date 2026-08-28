// ---------------------------------------------------------------------
//  perceptron_seq_item  --  one stimulus/response pair for the
//                            perceptron agent.
//
//  `inputs` is randomized by sequences and driven onto the DUT by the
//  driver. `out` is not randomized: the monitor fills it in after
//  sampling the DUT, and that's the copy the scoreboard checks.
// ---------------------------------------------------------------------
class perceptron_seq_item #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS];
         logic signed [DATA_WIDTH-1:0] out;

    `uvm_object_param_utils(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH))

    function new(string name = "perceptron_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("out=%0d | inputs=[", out);
        foreach (inputs[i])
            s = {s, $sformatf("%0d%s", inputs[i], (i == NUM_INPUTS-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to perceptron_seq_item failed")
        super.do_copy(rhs);
        inputs = rhs_.inputs;
        out    = rhs_.out;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (inputs == rhs_.inputs) && (out == rhs_.out);
    endfunction

endclass
