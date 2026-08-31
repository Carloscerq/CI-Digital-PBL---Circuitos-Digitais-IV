// ---------------------------------------------------------------------
//  cnn_top_base_test  --  builds the env. cnn_top's geometry
//  is fixed (DATA_WIDTH=24/FRAC_BITS=16/IMG_WIDTH=32/IMG_HEIGHT=32/
//  IN_CHANNELS=4/CHANNELS=8/OUT_CLASSES=4/IN_FEATURES=2048, see
//  cnn_top_pkg.sv), so like mlp_base_test/line_buffer_3x3_base_test
//  there's nothing to parameterize by inheritance.
//
//  cnn_top_directed_random_test  --  runs the directed real-
//  spectrogram frame first (cnn_top_directed_seq), then one
//  randomized-content frame (cnn_top_random_seq), same shape as
//  line_buffer_3x3_directed_random_test. The stimulus lives in
//  main_phase, not run_phase, because reset is applied in the driver's
//  reset_phase (see cnn_top_driver.sv): main_phase is the first
//  run-time phase that is guaranteed to start only after reset_phase
//  has dropped its objection, so no pixel is ever driven while reset is
//  still asserted. run_phase, which spans the whole run-time schedule,
//  would have overlapped reset instead. Both start_item()/finish_item()
//  calls returning only means the driver finished STREAMING the
//  frames' pixels in -- the pipeline's own latency means the second
//  frame's single output beat can still be in flight after that, so
//  the test explicitly waits for the scoreboard to have recorded both
//  frames' output beats (env.scoreboard.n_outputs) before dropping its
//  objection, with a generous real-time bound as a safety net against
//  hanging forever if a real bug ever stops output from ever arriving.
// ---------------------------------------------------------------------
class cnn_top_base_test extends uvm_test;

    `uvm_component_utils(cnn_top_base_test)

    cnn_top_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = cnn_top_env::type_id::create("env", this);
    endfunction

endclass

class cnn_top_directed_random_test extends cnn_top_base_test;

    `uvm_component_utils(cnn_top_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        cnn_top_directed_seq dseq;
        cnn_top_random_seq   rseq;
        int unsigned total_frames;

        phase.raise_objection(this);

        dseq = cnn_top_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = cnn_top_random_seq::type_id::create("rseq");
        rseq.num_frames = 1;
        rseq.start(env.agent.sequencer);

        total_frames = 1 + rseq.num_frames;

        fork
            wait (env.scoreboard.n_outputs >= total_frames);
            begin
                // Each frame is ~1024 cycles of input plus a small
                // pipeline-drain latency at 10ns/cycle -- 5ms is a huge
                // multiple of what two frames should ever need, so this
                // only fires on a genuine hang.
                #5_000_000;
                `uvm_error("TIMEOUT",
                    $sformatf("only %0d of %0d expected output frames observed before the safety timeout",
                              env.scoreboard.n_outputs, total_frames))
            end
        join_any
        disable fork;

        phase.drop_objection(this);
    endtask

endclass
