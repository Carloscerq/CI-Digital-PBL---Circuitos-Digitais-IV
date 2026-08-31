// ---------------------------------------------------------------------
//  line_buffer_3x3_seq_item  --  one whole frame of stimulus: every
//  pixel of the IMG_HEIGHT x IMG_WIDTH x IN_CHANNELS image the DUT will
//  walk over, matching the DUT's own frame-at-a-time behaviour (it
//  produces exactly IMG_WIDTH*IMG_HEIGHT windows per s_last-terminated
//  stream, so a single sequence item is the natural stimulus granularity
//  here -- unlike perceptron/mlp where one item is one vector).
//
//  Array shape is [row][col][channel], i.e. pixels[r][c][ch], mirroring
//  how tb_line_buffer_3x3.sv's feed_image() indexes its loop variables
//  (r, c, ch) and the raster order the DUT expects pixels in.
// ---------------------------------------------------------------------
class line_buffer_3x3_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] pixels [IMG_HEIGHT][IMG_WIDTH][IN_CHANNELS];

    `uvm_object_utils(line_buffer_3x3_seq_item)

    function new(string name = "line_buffer_3x3_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("line_buffer_3x3_seq_item: %0d x %0d x %0d frame",
                          IMG_HEIGHT, IMG_WIDTH, IN_CHANNELS);
    endfunction

    function void do_copy(uvm_object rhs);
        line_buffer_3x3_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to line_buffer_3x3_seq_item failed")
        super.do_copy(rhs);
        pixels = rhs_.pixels;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        line_buffer_3x3_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        foreach (pixels[r, c, ch])
            if (pixels[r][c][ch] !== rhs_.pixels[r][c][ch]) return 0;
        return 1;
    endfunction

endclass
