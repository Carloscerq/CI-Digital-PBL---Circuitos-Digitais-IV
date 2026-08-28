// ---------------------------------------------------------------------
//  dense_layer_fsm_seq_item  --  one whole frame of stimulus: all
//  IN_FEATURES/IN_CHANNELS = 256 pixels (IN_CHANNELS=8 values each) the
//  DUT consumes before it produces its single OUT_CLASSES-wide logits
//  beat, matching the DUT's own frame-at-a-time behaviour (like
//  line_buffer_3x3_seq_item / mlp_seq_item, a single sequence item is
//  the natural stimulus granularity here since the DUT only responds
//  once per whole stream).
//
//  Array shape is pixels[pixel_idx][ch], pixel_idx = 0..255,
//  ch = 0..IN_CHANNELS-1, mirroring the raster/stream order
//  feed_dense() in tb_dense_layer_fsm.sv drives beats in, and the exact
//  order the DUT's rom_addr sweep expects (feature index
//  f = pixel_idx*IN_CHANNELS + ch, see dense_layer_fsm_scoreboard.sv for
//  the full derivation).
//
//  `logits` is not randomized: the monitor fills it in from the single
//  observed output beat, and that's the copy the scoreboard checks.
// ---------------------------------------------------------------------
class dense_layer_fsm_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] pixels [NUM_PIXELS][IN_CHANNELS];
         logic signed [DATA_WIDTH-1:0] logits [OUT_CLASSES];

    `uvm_object_utils(dense_layer_fsm_seq_item)

    function new(string name = "dense_layer_fsm_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("dense_layer_fsm_seq_item: %0d pixels x %0d channels | logits=[",
                       NUM_PIXELS, IN_CHANNELS);
        foreach (logits[i])
            s = {s, $sformatf("%0d%s", logits[i], (i == OUT_CLASSES-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        dense_layer_fsm_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to dense_layer_fsm_seq_item failed")
        super.do_copy(rhs);
        pixels = rhs_.pixels;
        logits = rhs_.logits;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        dense_layer_fsm_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (pixels == rhs_.pixels) && (logits == rhs_.logits);
    endfunction

endclass
