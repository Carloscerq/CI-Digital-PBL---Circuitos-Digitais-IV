// ---------------------------------------------------------------------
//  conv2d_fsm_base_test  --  builds the env. conv2d_fsm's geometry is
//  fixed (DATA_WIDTH=24/FRAC_BITS=16/CHANNELS=8/IN_CHANNELS=4, see
//  conv2d_fsm_pkg.sv), so like mlp_base_test/line_buffer_3x3_base_test
//  there's nothing to parameterize by inheritance.
//
//  conv2d_fsm_directed_random_test  --  runs the small hand-computable
//  directed batch first (see conv2d_fsm_directed_seq: all-zero, +1.0,
//  -1.0 windows), then a randomized batch (see conv2d_fsm_random_seq),
//  same shape as mlp_directed_random_test/line_buffer_3x3_directed_random_test.
// ---------------------------------------------------------------------
class conv2d_fsm_base_test extends uvm_test;

    `uvm_component_utils(conv2d_fsm_base_test)

    conv2d_fsm_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = conv2d_fsm_env::type_id::create("env", this);
    endfunction

endclass

class conv2d_fsm_directed_random_test extends conv2d_fsm_base_test;

    `uvm_component_utils(conv2d_fsm_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        conv2d_fsm_directed_seq dseq;
        conv2d_fsm_random_seq   rseq;

        phase.raise_objection(this);

        dseq = conv2d_fsm_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = conv2d_fsm_random_seq::type_id::create("rseq");
        rseq.num_txns = 16;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
