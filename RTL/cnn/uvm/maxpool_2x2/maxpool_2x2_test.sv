// ---------------------------------------------------------------------
//  maxpool_2x2_base_test  --  builds the env. maxpool_2x2's geometry is
//  fixed (IMG_WIDTH=32/CHANNELS=8/DATA_WIDTH=24, see maxpool_2x2_pkg.sv),
//  so like line_buffer_3x3_base_test there's nothing to parameterize by
//  inheritance.
//
//  maxpool_2x2_directed_random_test  --  runs the deterministic directed
//  frame first (see maxpool_2x2_directed_seq, an exact reproduction of
//  tb_maxpool_2x2.sv's monotonic pixel pattern), then a small
//  randomized-content sweep with manufactured tie cases (see
//  maxpool_2x2_random_seq), same shape as line_buffer_3x3_directed_random_test.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  maxpool_2x2_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class maxpool_2x2_base_test extends uvm_test;

    `uvm_component_utils(maxpool_2x2_base_test)

    maxpool_2x2_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = maxpool_2x2_env::type_id::create("env", this);
    endfunction

endclass

class maxpool_2x2_directed_random_test extends maxpool_2x2_base_test;

    `uvm_component_utils(maxpool_2x2_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        maxpool_2x2_directed_seq dseq;
        maxpool_2x2_random_seq   rseq;

        phase.raise_objection(this);

        dseq = maxpool_2x2_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = maxpool_2x2_random_seq::type_id::create("rseq");
        rseq.num_frames = 2;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
