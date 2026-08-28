// ---------------------------------------------------------------------
//  dense_layer_fsm_directed_seq  --  reproduces tb_dense_layer_fsm.sv's
//  exact constant-1.0-input frame: every pixel/channel of the 256x8
//  frame is Q8.16 24'h01_0000. This is a useful cross-check even though
//  it has no hand-derivable expected value baked into the original tb
//  (the old hardcoded numeric check was removed once real trained
//  weights replaced placeholder ones, see tb_dense_layer_fsm.sv's
//  comment) -- dense_layer_fsm_scoreboard.sv computes the golden logits
//  from the very same $readmemh'd weight/bias files the DUT loads, so
//  this frame gets a real bit-exact check that the original tb
//  deliberately stopped short of.
//
//  dense_layer_fsm_random_seq  --  a small handful of frames (default 2)
//  with fully randomized pixel content, for coverage beyond the single
//  constant-input pattern. num_frames is public so a test can adjust
//  the sweep, mirroring line_buffer_3x3_random_seq/mlp_random_seq. Each
//  frame is 256*8 = 2048 scalar taps (plus the ROM's own 2048x4
//  weights), so this is already substantial simulated MAC activity per
//  item -- kept deliberately small.
// ---------------------------------------------------------------------
class dense_layer_fsm_directed_seq extends uvm_sequence #(dense_layer_fsm_seq_item);

    `uvm_object_utils(dense_layer_fsm_directed_seq)

    function new(string name = "dense_layer_fsm_directed_seq");
        super.new(name);
    endfunction

    task body();
        dense_layer_fsm_seq_item item;
        item = dense_layer_fsm_seq_item::type_id::create("item");

        for (int p = 0; p < NUM_PIXELS; p++)
            for (int ch = 0; ch < IN_CHANNELS; ch++)
                item.pixels[p][ch] = 24'h01_0000; // 1.0 in Q8.16

        start_item(item);
        finish_item(item);
    endtask

endclass

class dense_layer_fsm_random_seq extends uvm_sequence #(dense_layer_fsm_seq_item);

    `uvm_object_utils(dense_layer_fsm_random_seq)

    int unsigned num_frames = 2;

    function new(string name = "dense_layer_fsm_random_seq");
        super.new(name);
    endfunction

    task body();
        dense_layer_fsm_seq_item item;
        repeat (num_frames) begin
            item = dense_layer_fsm_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize dense_layer_fsm_seq_item frame")
            start_item(item);
            finish_item(item);
        end
    endtask

endclass
