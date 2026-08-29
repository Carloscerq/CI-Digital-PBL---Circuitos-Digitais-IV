// ---------------------------------------------------------------------
//  line_buffer_3x3_base_test  --  builds the env. line_buffer_3x3's
//  geometry is fixed (IMG_WIDTH=32/IMG_HEIGHT=32/IN_CHANNELS=4/
//  DATA_WIDTH=24, see line_buffer_3x3_pkg.sv), so like mlp_base_test
//  there's nothing to parameterize by inheritance.
//
//  line_buffer_3x3_directed_random_test  --  runs the deterministic
//  directed frame first (see line_buffer_3x3_directed_seq, an exact
//  reproduction of tb_line_buffer_3x3.sv's pixel pattern), then a small
//  randomized-content sweep (see line_buffer_3x3_random_seq), same
//  shape as mlp_directed_random_test.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  line_buffer_3x3_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class line_buffer_3x3_base_test extends uvm_test;

    `uvm_component_utils(line_buffer_3x3_base_test)

    line_buffer_3x3_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = line_buffer_3x3_env::type_id::create("env", this);
    endfunction

endclass

class line_buffer_3x3_directed_random_test extends line_buffer_3x3_base_test;

    `uvm_component_utils(line_buffer_3x3_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        line_buffer_3x3_directed_seq dseq;
        line_buffer_3x3_random_seq   rseq;

        phase.raise_objection(this);

        dseq = line_buffer_3x3_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = line_buffer_3x3_random_seq::type_id::create("rseq");
        rseq.num_frames = 2;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
