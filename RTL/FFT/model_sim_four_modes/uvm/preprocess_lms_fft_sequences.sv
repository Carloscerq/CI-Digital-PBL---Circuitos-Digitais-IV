// ---------------------------------------------------------------------
//  preprocess_lms_fft_directed_seq  --  streams a cheap, bounded-
//  amplitude triangle wave (integer math only, no need for a "real"
//  signal -- just something non-degenerate that stays well clear of
//  saturation) continuously for `num_samples` desired_sample beats.
//
//  num_samples defaults to 7000: comfortably inside the 6000-8000-beat
//  "generous, more-than-enough" range worked out from the DUT's
//  arithmetic (32:1 decimation means the first 64-sample frame needs
//  on the order of 64*32=2048 raw samples to fill, plus fixed pipeline
//  fill latency; subsequent frames emerge roughly every
//  HOP_SIZE*32=256 raw samples). This sequence deliberately does NOT
//  try to predict an exact frame count from that arithmetic -- see
//  preprocess_lms_fft_scoreboard.sv, which counts and validates
//  whatever number of frames actually completes instead.
//
//  Triangle wave: a `period`-sample triangle centered on zero,
//  amplitude bounded to +-(period/4)*scale = +-12,800 with the
//  defaults below -- about 0.15% of the full 24-bit signed range
//  (+-8,388,608), comfortably inside preprocess_lms_fft_seq_item's own
//  c_modest_amplitude constraint and nowhere near saturating any FIR/
//  Hann stage, so the monitor's "no spurious saturation event" check
//  stays meaningful.
//
//  preprocess_lms_fft_random_seq  --  a small handful of additional
//  beats with fully randomized (but still amplitude-bounded, see
//  preprocess_lms_fft_seq_item's c_modest_amplitude) desired_sample
//  content, mirroring the "one directed + a bit of random" shape used
//  by cnn_top_random_seq/line_buffer_3x3_random_seq. Kept small:
//  a handful of extra beats appended after a full directed run is
//  already plenty of additional coverage without materially extending
//  run time.
// ---------------------------------------------------------------------
class preprocess_lms_fft_directed_seq extends uvm_sequence #(preprocess_lms_fft_seq_item);

    `uvm_object_utils(preprocess_lms_fft_directed_seq)

    int unsigned num_samples = 7000;
    int unsigned period      = 256;
    int          scale       = 100;

    function new(string name = "preprocess_lms_fft_directed_seq");
        super.new(name);
    endfunction

    task body();
        preprocess_lms_fft_seq_item item;

        for (int unsigned i = 0; i < num_samples; i++) begin
            automatic int unsigned phase_in_period = i % period;
            automatic int unsigned triangle_height =
                (phase_in_period < (period / 2)) ?
                    phase_in_period : (period - phase_in_period);
            automatic int signed centered_height =
                int'(triangle_height) - int'(period / 4);
            automatic logic signed [DATA_WIDTH-1:0] sample_value =
                centered_height * scale;

            item = preprocess_lms_fft_seq_item::type_id::create($sformatf("item_%0d", i));
            item.desired_sample = sample_value;

            start_item(item);
            finish_item(item);
        end
    endtask

endclass

class preprocess_lms_fft_random_seq extends uvm_sequence #(preprocess_lms_fft_seq_item);

    `uvm_object_utils(preprocess_lms_fft_random_seq)

    int unsigned num_samples = 200;

    function new(string name = "preprocess_lms_fft_random_seq");
        super.new(name);
    endfunction

    task body();
        preprocess_lms_fft_seq_item item;
        repeat (num_samples) begin
            item = preprocess_lms_fft_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize preprocess_lms_fft_seq_item")
            start_item(item);
            finish_item(item);
        end
    endtask

endclass
