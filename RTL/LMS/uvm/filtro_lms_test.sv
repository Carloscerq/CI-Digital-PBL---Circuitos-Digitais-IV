// ---------------------------------------------------------------------
//  filtro_lms_base_test   -- builds the env.
//
//  filtro_lms_regression_test -- runs the directed 20-sample regression
//  pin ported from tb_filtro_lms.v, then a moderate-magnitude random
//  sweep (the sequence that actually exercises the adaptive tracking
//  math rather than mostly saturation clamps), then a wide/saturating
//  random sweep for extra saturation-path coverage.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  filtro_lms_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class filtro_lms_base_test extends uvm_test;

    `uvm_component_utils(filtro_lms_base_test)

    filtro_lms_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = filtro_lms_env::type_id::create("env", this);
    endfunction

endclass

class filtro_lms_regression_test extends filtro_lms_base_test;

    `uvm_component_utils(filtro_lms_regression_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        filtro_lms_directed_seq    dseq;
        filtro_lms_random_seq      rseq;
        filtro_lms_wide_random_seq wseq;

        phase.raise_objection(this);

        dseq = filtro_lms_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = filtro_lms_random_seq::type_id::create("rseq");
        rseq.num_samples = 30;
        rseq.start(env.agent.sequencer);

        wseq = filtro_lms_wide_random_seq::type_id::create("wseq");
        wseq.num_samples = 20;
        wseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
