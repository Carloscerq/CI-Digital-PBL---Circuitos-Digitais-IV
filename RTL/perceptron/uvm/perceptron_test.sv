// ---------------------------------------------------------------------
//  perceptron_base_test  --  builds the env; parameterized so a
//                             concrete test only has to fix NUM_INPUTS/
//                             DATA_WIDTH via inheritance.
//
//  perceptron_wide_random_test  --  the layer-0 configuration
//                                    (NUM_INPUTS=40, DATA_WIDTH=24)
//                                    driven by the top module: runs the
//                                    directed corner cases first, then a
//                                    500-vector constrained-random sweep.
// ---------------------------------------------------------------------
class perceptron_base_test #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_test;

    `uvm_component_param_utils(perceptron_base_test #(NUM_INPUTS, DATA_WIDTH))

    perceptron_env #(NUM_INPUTS, DATA_WIDTH) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = perceptron_env #(NUM_INPUTS, DATA_WIDTH)::type_id::create("env", this);
    endfunction

endclass

class perceptron_wide_random_test extends perceptron_base_test #(40, 24);

    `uvm_component_utils(perceptron_wide_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        perceptron_directed_seq #(40, 24) dseq;
        perceptron_random_seq #(40, 24)   rseq;

        phase.raise_objection(this);

        dseq = perceptron_directed_seq #(40, 24)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = perceptron_random_seq #(40, 24)::type_id::create("rseq");
        rseq.num_txns = 500;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
