// ---------------------------------------------------------------------
//  perceptron_directed_seq  --  hand-picked vectors that pin down the
//                                edges of perceptron.sv's fixed-point
//                                math: exact zero, saturate-high,
//                                ReLU-clamp, and the layer-0 wide-product
//                                regression vector from
//                                perceptron_tb_fixedpoint.sv (39370 on
//                                every one of the 40 inputs used to wrap
//                                to -2999215 before the accumulator was
//                                widened).
//
//  perceptron_random_seq  --  constrained-random full-range sweep, the
//                              UVM equivalent of that same testbench's
//                              500-vector loop, but unconstrained across
//                              negative values too, so it can also land
//                              in the ReLU-clamp branch (the original
//                              loop only sampled inputs >= 0).
// ---------------------------------------------------------------------
class perceptron_directed_seq #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_sequence #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH));

    `uvm_object_param_utils(perceptron_directed_seq #(NUM_INPUTS, DATA_WIDTH))

    function new(string name = "perceptron_directed_seq");
        super.new(name);
    endfunction

    task body();
        send_const(0);                                 // exact zero
        send_const((longint'(1) <<< (DATA_WIDTH-1)) - 1); // max positive -> saturate high
        send_const(-(longint'(1) <<< (DATA_WIDTH-1)));    // max negative -> ReLU clamp
        send_const(39370);                             // layer-0 wide-product regression
    endtask

    task send_const(longint signed value);
        perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) item;
        item = perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH)::type_id::create("item");
        start_item(item);
        if (!item.randomize() with { foreach (inputs[i]) inputs[i] == value; })
            `uvm_error("RAND", "directed item randomize failed")
        finish_item(item);
    endtask

endclass

class perceptron_random_seq #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_sequence #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH));

    `uvm_object_param_utils(perceptron_random_seq #(NUM_INPUTS, DATA_WIDTH))

    int unsigned num_txns = 500;

    function new(string name = "perceptron_random_seq");
        super.new(name);
    endfunction

    task body();
        perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) item;
        repeat (num_txns) begin
            item = perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH)::type_id::create("item");
            start_item(item);
            if (!item.randomize())
                `uvm_error("RAND", "random item randomize failed")
            finish_item(item);
        end
    endtask

endclass
