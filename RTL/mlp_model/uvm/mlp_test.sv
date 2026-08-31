// ---------------------------------------------------------------------
//  mlp_base_test  --  builds the env. MLP has exactly one valid
//                      geometry (tied to the trained weights in
//                      mlp_weights.sv), so unlike perceptron_base_test
//                      there's nothing to parameterize by inheritance.
//
//  mlp_directed_random_test  --  runs the 7 directed corner cases first
//                                 (see mlp_directed_seq), then a
//                                 300-vector constrained-random sweep
//                                 (see mlp_random_seq), same shape as
//                                 perceptron_wide_random_test.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  mlp_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class mlp_base_test extends uvm_test;

    `uvm_component_utils(mlp_base_test)

    mlp_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mlp_env::type_id::create("env", this);
    endfunction

endclass

class mlp_directed_random_test extends mlp_base_test;

    `uvm_component_utils(mlp_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        mlp_directed_seq dseq;
        mlp_random_seq   rseq;

        phase.raise_objection(this);

        dseq = mlp_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = mlp_random_seq::type_id::create("rseq");
        rseq.num_txns = 300;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
