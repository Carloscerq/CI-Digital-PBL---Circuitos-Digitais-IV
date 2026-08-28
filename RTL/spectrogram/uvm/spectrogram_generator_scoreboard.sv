// ---------------------------------------------------------------------
//  spectrogram_generator_scoreboard  --  generalizes
//  tb_spectrogram_generator.sv's monitor_cnn_frames() check: rather than
//  re-deriving each expected word from the closed-form
//  spec_idx*10000 + frame*100 + bin pattern (which only works for that
//  one directed pattern), it checks the observed output stream directly
//  against whatever words the driver actually sent, in order -- valid
//  for arbitrary, including fully random, frame content, since this DUT
//  is a pure identity passthrough at the frame level (see
//  spectrogram_generator.sv's own header comment).
//
//  frame_export (fed by the driver's frame_ap, once per frame, the
//  instant it starts streaming) pushes each frame's whole 1024-word
//  array onto frame_q, a FIFO of driven-but-not-yet-fully-confirmed
//  frames. More than one frame can be queued at once: the driver may
//  already be streaming frame N+1 into the write-side buffer while
//  frame N is still draining out the read side -- that concurrency is
//  the ping-pong buffer's whole point -- so this scoreboard does not
//  assume "one frame in flight at a time" the way
//  line_buffer_3x3_scoreboard.sv (whose DUT has no such buffering) can.
//
//  word_export (fed by the monitor's ap, once per accepted output word,
//  in arrival order) always compares against frame_q[0][pos]: position
//  `pos` walks 0..MEM_DEPTH-1 through the queue's front frame and resets
//  to 0 every time a word arrives with m_axis_last set, at which point
//  that frame is popped off the front of the queue -- this is how "every
//  word, in order, for arbitrary content" is checked without needing any
//  arithmetic pattern to reconstruct the expected value. A word count
//  that reaches MEM_DEPTH without m_axis_last ever having been seen (a
//  hypothetical DUT bug -- spectrogram_generator.sv's rd_count
//  wraparound guarantees this never happens against a correct DUT) is
//  treated the same way, so `pos` can never walk off the end of the
//  1024-word golden array.
// ---------------------------------------------------------------------

`uvm_analysis_imp_decl(_frame)
`uvm_analysis_imp_decl(_word)

class spectrogram_generator_scoreboard extends uvm_component;

    `uvm_component_utils(spectrogram_generator_scoreboard)

    uvm_analysis_imp_frame #(spectrogram_generator_seq_item, spectrogram_generator_scoreboard) frame_export;
    uvm_analysis_imp_word  #(spectrogram_generator_word_item, spectrogram_generator_scoreboard) word_export;

    // FIFO of driven frames (ground truth); frame_q[0] is the frame
    // currently being confirmed out.
    spectrogram_word_arr_t frame_q [$];

    int unsigned pos;              // position 0..MEM_DEPTH-1 within frame_q[0]
    int unsigned frame_count;      // frames driven in (pushed onto frame_q)
    int unsigned frames_out;       // frames fully confirmed out (popped off frame_q)
    int unsigned total_words;
    int unsigned mismatch_count;
    int unsigned last_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        frame_export = new("frame_export", this);
        word_export  = new("word_export", this);
    endfunction

    // --- driver's ground-truth frame, pushed onto the FIFO -------------
    function void write_frame(spectrogram_generator_seq_item t);
        frame_q.push_back(t.words);
        frame_count++;
    endfunction

    // --- monitor's observed output word ---------------------------------
    function void write_word(spectrogram_generator_word_item t);
        logic signed [DATA_WIDTH-1:0] expected;
        bit frame_done;

        if (frame_q.size() == 0)
            `uvm_fatal("NOFRAME", "output word observed before any frame was published by the driver")

        expected = frame_q[0][pos];
        if (t.data !== expected) begin
            mismatch_count++;
            `uvm_error("MISMATCH",
                $sformatf("frame %0d position %0d: expected %0d, got %0d",
                          frames_out, pos, expected, t.data))
        end

        total_words++;
        pos++;

        // A frame is confirmed done either the normal way (m_axis_last
        // on the MEM_DEPTH-th word) or, defensively, once MEM_DEPTH
        // words have been seen regardless of m_axis_last -- see the
        // file header for why the latter can never trigger against a
        // correct DUT but keeps `pos` from ever indexing past the end
        // of the 1024-word golden frame.
        frame_done = t.last || (pos == MEM_DEPTH);

        if (frame_done) begin
            if (pos != MEM_DEPTH) begin
                last_errors++;
                `uvm_error("LAST",
                    $sformatf("frame %0d: m_axis_last asserted at word %0d (expected at word %0d)",
                              frames_out, pos, MEM_DEPTH))
            end else if (!t.last) begin
                last_errors++;
                `uvm_error("LAST",
                    $sformatf("frame %0d: m_axis_last not asserted at word %0d (the last word of the frame)",
                              frames_out, MEM_DEPTH))
            end
            void'(frame_q.pop_front());
            pos = 0;
            frames_out++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("frames_in=%0d frames_out=%0d total_words=%0d mismatches=%0d last_errors=%0d",
                      frame_count, frames_out, total_words, mismatch_count, last_errors), UVM_LOW)

        if (frames_out == 0)
            `uvm_error("SCOREBOARD", "no frames were fully streamed out")

        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d word mismatch(es) between input and output streams", mismatch_count))

        if (last_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d m_axis_last placement error(s)", last_errors))

        if (frame_q.size() != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d frame(s) driven in but never fully streamed out", frame_q.size()))
    endfunction

endclass
