// ---------------------------------------------------------------------
//  spectrogram_generator_directed_seq  --  reproduces
//  tb_spectrogram_generator.sv's exact closed-form data pattern
//  (data = spec_idx*10000 + frame*100 + bin) for one full 1024-word
//  frame. A cheap regression pin against that specific arithmetic
//  pattern, kept even though spectrogram_generator_scoreboard.sv's
//  generic "output stream == input stream, word for word, in order"
//  check no longer needs this particular closed form to catch a bug --
//  see that file's header and the DUT's own header comment for why a
//  pure identity passthrough doesn't need pattern-specific golden math.
//
//  spectrogram_generator_random_seq  --  2-3 (default 3) back-to-back
//  frames of fully randomized word content, one seq_item::randomize()
//  call per frame. This is the part that actually stresses the
//  ping-pong swap logic (spectrogram_generator.sv's wr_side/rd_side
//  toggling under feed/drain timing that isn't tied to any predictable
//  pattern) -- kept to a small handful of frames since each one is
//  already 1024 words of simulated activity, same "small handful, not
//  more" reasoning smma_cnn_top_random_seq/line_buffer_3x3_random_seq
//  use.
// ---------------------------------------------------------------------
class spectrogram_generator_directed_seq extends uvm_sequence #(spectrogram_generator_seq_item);

    `uvm_object_utils(spectrogram_generator_directed_seq)

    // Spectrogram index folded into the closed-form pattern, matching
    // feed_fft_frames()'s `s * 10000` term (s = spec_idx here).
    int unsigned spec_idx = 0;

    function new(string name = "spectrogram_generator_directed_seq");
        super.new(name);
    endfunction

    task body();
        spectrogram_generator_seq_item item;
        item = spectrogram_generator_seq_item::type_id::create("item");

        for (int f = 0; f < FRAMES_PER_SPECTROGRAM; f++) begin
            for (int b = 0; b < BINS_PER_FRAME; b++) begin
                item.words[(f * BINS_PER_FRAME) + b] =
                    DATA_WIDTH'((spec_idx * 10000) + (f * 100) + b);
            end
        end

        start_item(item);
        finish_item(item);
    endtask

endclass

class spectrogram_generator_random_seq extends uvm_sequence #(spectrogram_generator_seq_item);

    `uvm_object_utils(spectrogram_generator_random_seq)

    int unsigned num_frames = 3;

    function new(string name = "spectrogram_generator_random_seq");
        super.new(name);
    endfunction

    task body();
        spectrogram_generator_seq_item item;
        repeat (num_frames) begin
            item = spectrogram_generator_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize spectrogram_generator_seq_item frame")
            start_item(item);
            finish_item(item);
        end
    endtask

endclass
