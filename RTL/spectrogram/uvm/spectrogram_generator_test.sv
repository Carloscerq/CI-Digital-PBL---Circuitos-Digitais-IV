// ---------------------------------------------------------------------
//  spectrogram_generator_base_test  --  builds the env. The DUT's
//  geometry is fixed (DATA_WIDTH=24/BINS_PER_FRAME=32/
//  FRAMES_PER_SPECTROGRAM=32, see spectrogram_generator_pkg.sv), so like
//  cnn_top_base_test/mlp_base_test there's nothing to parameterize
//  by inheritance.
//
//  spectrogram_generator_directed_random_test  --  runs the one directed
//  closed-form-pattern frame (spectrogram_generator_directed_seq) first,
//  then num_frames randomized-content frames
//  (spectrogram_generator_random_seq), same shape as
//  cnn_top_directed_random_test / line_buffer_3x3_directed_random_test.
//  start_item()/finish_item() returning only means the driver finished
//  STREAMING a frame's words in -- the ping-pong buffer's own drain
//  latency (plus randomized bursty input gaps and output backpressure)
//  means the last frame's words can still be arriving well after that,
//  so this test explicitly waits for the scoreboard to have confirmed
//  every expected frame fully out (env.scoreboard.frames_out) before
//  dropping its objection, with a generous real-time bound as a safety
//  net against hanging forever if a real bug ever stops output from
//  arriving.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  spectrogram_generator_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class spectrogram_generator_base_test extends uvm_test;

    `uvm_component_utils(spectrogram_generator_base_test)

    spectrogram_generator_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spectrogram_generator_env::type_id::create("env", this);
    endfunction

endclass

class spectrogram_generator_directed_random_test extends spectrogram_generator_base_test;

    `uvm_component_utils(spectrogram_generator_directed_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        spectrogram_generator_directed_seq dseq;
        spectrogram_generator_random_seq   rseq;
        int unsigned total_frames;

        phase.raise_objection(this);

        dseq = spectrogram_generator_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = spectrogram_generator_random_seq::type_id::create("rseq");
        rseq.num_frames = 3;
        rseq.start(env.agent.sequencer);

        total_frames = 1 + rseq.num_frames;

        fork
            wait (env.scoreboard.frames_out >= total_frames);
            begin
                // MEM_DEPTH (1024) cycles/frame plus randomized bursty
                // input gaps and ~66% output backpressure, at 10ns/cycle
                // -- a huge multiple of what 4 frames should ever need,
                // so this only fires on a genuine hang.
                #20_000_000;
                `uvm_error("TIMEOUT",
                    $sformatf("only %0d of %0d expected frames confirmed out before the safety timeout",
                              env.scoreboard.frames_out, total_frames))
            end
        join_any
        disable fork;

        phase.drop_objection(this);
    endtask

endclass
