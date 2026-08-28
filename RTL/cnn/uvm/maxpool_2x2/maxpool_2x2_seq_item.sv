// ---------------------------------------------------------------------
//  maxpool_2x2_seq_item  --  one whole frame of stimulus: every pixel
//  of the IMG_WIDTH x IMG_WIDTH x CHANNELS image the DUT will walk over,
//  matching the DUT's own frame-at-a-time behaviour (it produces
//  exactly (IMG_WIDTH/2)*(IMG_WIDTH/2) pooled outputs per
//  s_last-terminated stream, so a single sequence item is the natural
//  stimulus granularity here, same shape as line_buffer_3x3_seq_item).
//
//  Array shape is [row][col][channel], i.e. pixels[r][c][ch], mirroring
//  how tb_maxpool_2x2.sv's feed_pool() indexes its loop variables
//  (r, c, ch) and the raster order the DUT expects pixels in.
// ---------------------------------------------------------------------
class maxpool_2x2_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] pixels [IMG_WIDTH][IMG_WIDTH][CHANNELS];

    `uvm_object_utils(maxpool_2x2_seq_item)

    function new(string name = "maxpool_2x2_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("maxpool_2x2_seq_item: %0d x %0d x %0d frame",
                          IMG_WIDTH, IMG_WIDTH, CHANNELS);
    endfunction

    function void do_copy(uvm_object rhs);
        maxpool_2x2_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to maxpool_2x2_seq_item failed")
        super.do_copy(rhs);
        pixels = rhs_.pixels;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        maxpool_2x2_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (pixels == rhs_.pixels);
    endfunction

endclass
