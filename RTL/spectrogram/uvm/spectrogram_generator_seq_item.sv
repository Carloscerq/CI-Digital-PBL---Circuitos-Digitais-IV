// ---------------------------------------------------------------------
//  spectrogram_generator_seq_item  --  one item = one whole 1024-word
//  spectrogram frame (BINS_PER_FRAME*FRAMES_PER_SPECTROGRAM =
//  32*32 = MEM_DEPTH), matching the DUT's own frame-at-a-time behaviour:
//  a ping-pong buffer fills/drains exactly MEM_DEPTH words per frame
//  before swapping sides (see spectrogram_generator.sv's wr_addr/
//  rd_count wraparound) -- the same "one item = one frame" granularity
//  smma_cnn_top_seq_item / line_buffer_3x3_seq_item use.
//
//  `words` is the randomized/directed stimulus the driver streams onto
//  s_axis_data, one element per cycle, in order (see
//  spectrogram_generator_driver.sv). Since this DUT is a pure identity
//  passthrough at the frame level -- whatever goes in via s_axis_data
//  comes back out via m_axis_data, same order, once the buffer that
//  holds it fills (see spectrogram_generator.sv's own header comment) --
//  there is no separate "expected result" field to fill in here: the
//  scoreboard checks the monitor's observed output stream directly
//  against this same `words` array (see
//  spectrogram_generator_scoreboard.sv), rather than against some
//  derived/computed golden value the way mac_seq_item/mlp_seq_item do.
// ---------------------------------------------------------------------
class spectrogram_generator_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] words [MEM_DEPTH];

    `uvm_object_utils(spectrogram_generator_seq_item)

    function new(string name = "spectrogram_generator_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("spectrogram_generator_seq_item: %0d words, words[0]=%0d words[%0d]=%0d",
                          MEM_DEPTH, words[0], MEM_DEPTH-1, words[MEM_DEPTH-1]);
    endfunction

    function void do_copy(uvm_object rhs);
        spectrogram_generator_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to spectrogram_generator_seq_item failed")
        super.do_copy(rhs);
        words = rhs_.words;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        spectrogram_generator_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (words == rhs_.words);
    endfunction

endclass

// ---------------------------------------------------------------------
//  spectrogram_generator_word_item  --  one observed output beat, built
//  by spectrogram_generator_monitor.sv, one per accepted m_axis word, in
//  arrival order. Deliberately a separate, much lighter object than
//  spectrogram_generator_seq_item (which carries a whole 1024-word
//  frame): the scoreboard's `uvm_analysis_imp_decl`-based word_export
//  needs its own distinct item type, the same "driver publishes ground
//  truth on one analysis port, monitor publishes per-beat observations
//  on a differently-typed one, both feeding one scoreboard" split
//  line_buffer_3x3_scoreboard.sv uses (line_buffer_3x3_seq_item vs.
//  line_buffer_3x3_window_item).
// ---------------------------------------------------------------------
class spectrogram_generator_word_item extends uvm_sequence_item;

    logic signed [DATA_WIDTH-1:0] data;
    bit                           last;

    `uvm_object_utils(spectrogram_generator_word_item)

    function new(string name = "spectrogram_generator_word_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("spectrogram_generator_word_item: data=%0d last=%0b", data, last);
    endfunction

endclass
