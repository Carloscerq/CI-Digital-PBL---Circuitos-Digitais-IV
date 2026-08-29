// ---------------------------------------------------------------------
//  preprocess_lms_fft_base_test  --  builds the env. This testbench
//  targets exactly one DUT configuration (USE_LMS=0, DATA_WIDTH=24/
//  FRAC_BITS=15/NORMALIZE=1/HOP_SIZE=8 -- see
//  tb/preprocess_lms_fft_uvm_top.sv), so, like smma_cnn_top_base_test,
//  there's nothing to parameterize by inheritance.
//
//  preprocess_lms_fft_directed_test  --  runs the directed
//  triangle-wave stream (preprocess_lms_fft_directed_seq, 7000 beats)
//  followed by a short randomized-content tail
//  (preprocess_lms_fft_random_seq, 200 beats), then waits a generous
//  drain period for the pipeline to fully empty before checking the
//  loose pipeline_busy liveness invariant (busy must have gone back to
//  0 by then -- see preprocess_lms_fft_monitor.sv's busy_last/
//  busy_ever_seen). A safety timeout wraps the whole thing so a real
//  hang (e.g. desired_ready or fft_ready never toggling) fails cleanly
//  instead of running forever; 50,000,000ns at the tb's 10ns clock
//  period is 5,000,000 cycles, a huge multiple of what streaming ~7200
//  beats plus pipeline drain should ever need.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  preprocess_lms_fft_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class preprocess_lms_fft_base_test extends uvm_test;

    `uvm_component_utils(preprocess_lms_fft_base_test)

    preprocess_lms_fft_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = preprocess_lms_fft_env::type_id::create("env", this);
    endfunction

endclass

class preprocess_lms_fft_directed_test extends preprocess_lms_fft_base_test;

    `uvm_component_utils(preprocess_lms_fft_directed_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        preprocess_lms_fft_directed_seq dseq;
        preprocess_lms_fft_random_seq   rseq;

        phase.raise_objection(this);

        fork
            begin : stimulus_and_drain
                dseq = preprocess_lms_fft_directed_seq::type_id::create("dseq");
                dseq.start(env.agent.sequencer);

                rseq = preprocess_lms_fft_random_seq::type_id::create("rseq");
                rseq.num_samples = 200;
                rseq.start(env.agent.sequencer);

                // Generous drain: give the pipeline plenty of idle time
                // to finish whatever frame is still in flight after the
                // last input beat was accepted.
                #100_000;

                if (env.agent.monitor.busy_last)
                    `uvm_error("BUSY_END",
                        "pipeline_busy still asserted after the drain period -- pipeline did not return to idle")
            end
            begin : safety_timeout
                #50_000_000;
                `uvm_error("TIMEOUT",
                    "test did not complete within the safety time bound")
            end
        join_any
        disable fork;

        phase.drop_objection(this);
    endtask

endclass
