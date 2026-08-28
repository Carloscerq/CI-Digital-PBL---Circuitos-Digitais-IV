// ---------------------------------------------------------------------
//  dense_layer_fsm_base_test  --  builds the env. dense_layer_fsm's
//  geometry is fixed (DATA_WIDTH=24/FRAC_BITS=16/IN_CHANNELS=8/
//  OUT_CLASSES=4/IN_FEATURES=2048, see dense_layer_fsm_pkg.sv), so like
//  conv2d_fsm_base_test/mlp_base_test there's nothing to parameterize by
//  inheritance.
//
//  dense_layer_fsm_directed_random_test  --  runs the directed,
//  hand-reproducible constant-1.0-Q8.16 frame first (see
//  dense_layer_fsm_directed_seq, matching tb_dense_layer_fsm.sv's
//  feed_dense() exactly), then a couple of randomized-content frames
//  (see dense_layer_fsm_random_seq), same shape as
//  conv2d_fsm_directed_random_test/mlp_directed_random_test.
// ---------------------------------------------------------------------
class dense_layer_fsm_base_test extends uvm_test;

    `uvm_component_utils(dense_layer_fsm_base_test)

    dense_layer_fsm_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = dense_layer_fsm_env::type_id::create("env", this);
    endfunction

endclass

class dense_layer_fsm_directed_random_test extends dense_layer_fsm_base_test;

    `uvm_component_utils(dense_layer_fsm_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        dense_layer_fsm_directed_seq dseq;
        dense_layer_fsm_random_seq   rseq;

        phase.raise_objection(this);

        dseq = dense_layer_fsm_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = dense_layer_fsm_random_seq::type_id::create("rseq");
        rseq.num_frames = 2;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
