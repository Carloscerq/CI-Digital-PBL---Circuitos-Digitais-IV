// ---------------------------------------------------------------------
//  line_buffer_3x3_directed_seq  --  reproduces tb_line_buffer_3x3.sv's
//  exact deterministic pixel pattern, pixels[r][c][ch] = (r*IMG_WIDTH +
//  c + 1) + ch*1000, so the golden reconstruction in the scoreboard has
//  an exact, hand-traceable frame to check against (the original tb's
//  hand-computed "first window" expected values fall out of this same
//  formula).
//
//  line_buffer_3x3_random_seq  --  a small handful of frames (default 2)
//  with fully randomized pixel content, for basic additional coverage
//  beyond the one deterministic pattern. num_frames is public so a test
//  can adjust the sweep, mirroring mlp_random_seq/perceptron_random_seq.
//  Each frame is a full 1024-pixel stream, so this is already a lot of
//  simulated activity per item -- kept deliberately small.
// ---------------------------------------------------------------------
class line_buffer_3x3_directed_seq extends uvm_sequence #(line_buffer_3x3_seq_item);

    `uvm_object_utils(line_buffer_3x3_directed_seq)

    function new(string name = "line_buffer_3x3_directed_seq");
        super.new(name);
    endfunction

    task body();
        line_buffer_3x3_seq_item item;
        item = line_buffer_3x3_seq_item::type_id::create("item");

        for (int r = 0; r < IMG_HEIGHT; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                for (int ch = 0; ch < IN_CHANNELS; ch++)
                    item.pixels[r][c][ch] = (r * IMG_WIDTH + c + 1) + (ch * 1000);

        start_item(item);
        finish_item(item);
    endtask

endclass

class line_buffer_3x3_random_seq extends uvm_sequence #(line_buffer_3x3_seq_item);

    `uvm_object_utils(line_buffer_3x3_random_seq)

    int unsigned num_frames = 2;

    function new(string name = "line_buffer_3x3_random_seq");
        super.new(name);
    endfunction

    task body();
        line_buffer_3x3_seq_item item;
        repeat (num_frames) begin
            item = line_buffer_3x3_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize line_buffer_3x3_seq_item frame")
            start_item(item);
            finish_item(item);
        end
    endtask

endclass
