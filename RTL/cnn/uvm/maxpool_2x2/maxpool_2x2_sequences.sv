// ---------------------------------------------------------------------
//  maxpool_2x2_directed_seq  --  reproduces tb_maxpool_2x2.sv's exact
//  deterministic pixel pattern, pixels[r][c][ch] = r*IMG_WIDTH + c + 1
//  (identical across all CHANNELS channels), so this testbench has an
//  exact regression pin against the original tb's closed-form expected
//  value: because the pattern is strictly monotonically increasing in
//  raster order, the max of every 2x2 block is always its bottom-right
//  pixel, (r_out*2+1)*IMG_WIDTH + c_out*2 + 2. The scoreboard here
//  doesn't rely on that shortcut (it recomputes a genuine max of 4 from
//  the driven pixel array), but this sequence still exercises the exact
//  same stimulus the original directed tb used.
//
//  maxpool_2x2_random_seq  --  a small handful of frames (default 2)
//  with genuinely randomized, non-monotonic per-channel pixel content,
//  so the DUT's max-of-4 comparator tree is exercised on arbitrary
//  values rather than a pattern where the answer is always "bottom
//  right". After randomizing each frame, ~1/4 of its 2x2 blocks
//  (chosen per block, per channel) are additionally patched so that two
//  diagonally-opposite corners (top-left and bottom-right) of the block
//  are forced equal to the block's maximum -- deliberately manufacturing
//  duplicate/tied max values so the comparator tree's tie-handling
//  (ties don't affect the numeric result, since tied values are equal,
//  but they do exercise a code path the scoreboard's covergroup tracks
//  explicitly, see maxpool_2x2_scoreboard.sv) gets real coverage rather
//  than relying on plain randomization to stumble into a tie by luck (a
//  1-in-2^24 event with signed 24-bit channels). num_frames is public
//  so a test can adjust the sweep, mirroring
//  line_buffer_3x3_random_seq/mlp_random_seq.
// ---------------------------------------------------------------------
class maxpool_2x2_directed_seq extends uvm_sequence #(maxpool_2x2_seq_item);

    `uvm_object_utils(maxpool_2x2_directed_seq)

    function new(string name = "maxpool_2x2_directed_seq");
        super.new(name);
    endfunction

    task body();
        maxpool_2x2_seq_item item;
        item = maxpool_2x2_seq_item::type_id::create("item");

        for (int r = 0; r < IMG_WIDTH; r++)
            for (int c = 0; c < IMG_WIDTH; c++)
                for (int ch = 0; ch < CHANNELS; ch++)
                    item.pixels[r][c][ch] = (r * IMG_WIDTH + c + 1);

        start_item(item);
        finish_item(item);
    endtask

endclass

class maxpool_2x2_random_seq extends uvm_sequence #(maxpool_2x2_seq_item);

    `uvm_object_utils(maxpool_2x2_random_seq)

    int unsigned num_frames = 2;

    function new(string name = "maxpool_2x2_random_seq");
        super.new(name);
    endfunction

    task body();
        maxpool_2x2_seq_item item;

        repeat (num_frames) begin
            item = maxpool_2x2_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize maxpool_2x2_seq_item frame")

            // Manufacture tied-max 2x2 blocks: for ~1/4 of the blocks,
            // force the top-left and bottom-right corners equal to the
            // block's max (per channel), so the "which corner won"
            // coverage in the scoreboard sees genuine ties.
            for (int r = 0; r < IMG_WIDTH; r += 2) begin
                for (int c = 0; c < IMG_WIDTH; c += 2) begin
                    if ($urandom_range(0, 3) == 0) begin
                        for (int ch = 0; ch < CHANNELS; ch++) begin
                            logic signed [DATA_WIDTH-1:0] mx;
                            mx = item.pixels[r][c][ch];
                            if (item.pixels[r][c+1][ch]   > mx) mx = item.pixels[r][c+1][ch];
                            if (item.pixels[r+1][c][ch]   > mx) mx = item.pixels[r+1][c][ch];
                            if (item.pixels[r+1][c+1][ch] > mx) mx = item.pixels[r+1][c+1][ch];

                            item.pixels[r][c][ch]     = mx;
                            item.pixels[r+1][c+1][ch] = mx;
                        end
                    end
                end
            end

            start_item(item);
            finish_item(item);
        end
    endtask

endclass
