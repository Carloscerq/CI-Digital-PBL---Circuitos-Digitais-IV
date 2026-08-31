// ---------------------------------------------------------------------
//  cnn_top_seq_item  --  one whole frame of stimulus: every pixel
//  of the IMG_HEIGHT x IMG_WIDTH x IN_CHANNELS spectrogram the DUT will
//  walk over, matching the DUT's own frame-at-a-time behaviour (the
//  whole 4-stage pipeline produces exactly ONE output beat per
//  s_axis_last-terminated 1024-pixel stream), same "one item = one
//  frame" granularity as line_buffer_3x3_seq_item.
//
//  Array shape is [row][col][channel], mirroring both
//  tb_cnn_top.sv's raster-order flattening (tb_image_data[(i*4)+ch])
//  and line_buffer_3x3_seq_item's own [r][c][ch] convention.
//
//  This testbench is a protocol/integration-level testbench, not a
//  bit-exact one (see cnn_top_scoreboard.sv for why -- the 4
//  per-stage sibling UVM testbenches under RTL/cnn/uvm/ already verify
//  each stage's math bit-exact). Accordingly this item does double duty:
//   - `pixels` is the randomized/directed stimulus the driver streams in
//     (see cnn_top_driver.sv);
//   - the logit_*/last/probe_dense/input_beats_accepted fields are NOT
//     randomized -- they're left at their default (0) on driven items,
//     and are instead filled in on a *separate* item instance created by
//     the monitor once the frame's single output beat is observed (see
//     cnn_top_monitor.sv), the same "monitor independently samples
//     and fills the result fields" split mlp_seq_item/mlp_monitor use
//     (rather than the driver's own req item being reused/mutated).
// ---------------------------------------------------------------------
class cnn_top_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] pixels [IMG_HEIGHT][IMG_WIDTH][IN_CHANNELS];

    // --- result fields, filled in by the monitor -- not part of the
    //     driven stimulus, see class header above ---
    logic signed [DATA_WIDTH-1:0] logit_normal;
    logic signed [DATA_WIDTH-1:0] logit_unbalance;
    logic signed [DATA_WIDTH-1:0] logit_misalign;
    logic signed [DATA_WIDTH-1:0] logit_bearing;
    logic signed [DATA_WIDTH-1:0] probe_dense [OUT_CLASSES]; // dense_data[0..3], see cnn_top_if.sv
    bit                           last;
    int unsigned                  input_beats_accepted; // independently counted on s_axis, see monitor

    `uvm_object_utils(cnn_top_seq_item)

    function new(string name = "cnn_top_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("cnn_top_seq_item: frame=%0dx%0dx%0d | logits(n,u,mi,b)=(%0d,%0d,%0d,%0d) last=%0b beats=%0d",
                          IMG_HEIGHT, IMG_WIDTH, IN_CHANNELS,
                          logit_normal, logit_unbalance, logit_misalign, logit_bearing,
                          last, input_beats_accepted);
    endfunction

    function void do_copy(uvm_object rhs);
        cnn_top_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to cnn_top_seq_item failed")
        super.do_copy(rhs);
        pixels                = rhs_.pixels;
        logit_normal          = rhs_.logit_normal;
        logit_unbalance       = rhs_.logit_unbalance;
        logit_misalign        = rhs_.logit_misalign;
        logit_bearing         = rhs_.logit_bearing;
        probe_dense           = rhs_.probe_dense;
        last                  = rhs_.last;
        input_beats_accepted  = rhs_.input_beats_accepted;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        cnn_top_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (logit_normal == rhs_.logit_normal) &&
               (logit_unbalance == rhs_.logit_unbalance) &&
               (logit_misalign == rhs_.logit_misalign) &&
               (logit_bearing == rhs_.logit_bearing) &&
               (last == rhs_.last);
    endfunction

endclass
