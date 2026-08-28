// ---------------------------------------------------------------------
//  conv2d_fsm_directed_seq  --  a small hand-computable batch: an
//  all-zero window, a constant +1.0 (Q8.16) window, and a constant
//  -1.0 (Q8.16) window -- the same constant patterns tb_conv2d_fsm.sv's
//  feed_windows(count, positive) drives (24'h01_0000 / 24'hFF_0000),
//  just now split into two separate directed items instead of one
//  repeated value, plus the all-zero case tb_conv2d_fsm.sv never tried.
//  `is_last` is set on the final item so the batch's m_last placement
//  is exercised end to end. Meant to build confidence in the golden
//  model against easy-to-hand-check sums before trusting it against
//  the real trained weights via conv2d_fsm_random_seq below.
//
//  conv2d_fsm_random_seq  --  a batch of `num_txns` random windows,
//  `is_last` set on the last one, mirroring feed_windows()'s batching.
//  Full-range 24-bit taps summed over IN_CHANNELS*9+1 = 37 MAC terms
//  saturate the 48-bit accumulator almost unconditionally, so roughly
//  1-in-4 windows are constrained to a small magnitude (+-0.125 in
//  Q8.16) to keep the scoreboard's "not saturated" coverage bin
//  reachable alongside the (dominant) saturating case.
// ---------------------------------------------------------------------
class conv2d_fsm_directed_seq extends uvm_sequence #(conv2d_fsm_seq_item);

    `uvm_object_utils(conv2d_fsm_directed_seq)

    function new(string name = "conv2d_fsm_directed_seq");
        super.new(name);
    endfunction

    task body();
        conv2d_fsm_seq_item item;
        logic signed [23:0] plus_one, minus_one;

        plus_one  = 24'h01_0000; // +1.0 in Q8.16
        minus_one = 24'hFF_0000; // -1.0 in Q8.16

        // 0: all-zero window
        item = conv2d_fsm_seq_item::type_id::create("item");
        foreach (item.window[ch,r,c]) item.window[ch][r][c] = '0;
        item.is_last = 1'b0;
        start_item(item); finish_item(item);

        // 1: constant +1.0 window
        item = conv2d_fsm_seq_item::type_id::create("item");
        foreach (item.window[ch,r,c]) item.window[ch][r][c] = plus_one;
        item.is_last = 1'b0;
        start_item(item); finish_item(item);

        // 2: constant -1.0 window (last of this batch)
        item = conv2d_fsm_seq_item::type_id::create("item");
        foreach (item.window[ch,r,c]) item.window[ch][r][c] = minus_one;
        item.is_last = 1'b1;
        start_item(item); finish_item(item);
    endtask

endclass

class conv2d_fsm_random_seq extends uvm_sequence #(conv2d_fsm_seq_item);

    `uvm_object_utils(conv2d_fsm_random_seq)

    int unsigned num_txns = 16;

    function new(string name = "conv2d_fsm_random_seq");
        super.new(name);
    endfunction

    task body();
        conv2d_fsm_seq_item item;
        bit small_win;

        for (int i = 0; i < num_txns; i++) begin
            item = conv2d_fsm_seq_item::type_id::create("item");

            small_win = ($urandom_range(0, 3) == 0);
            if (small_win) begin
                if (!item.randomize() with {
                        foreach (window[ch,r,c])
                            window[ch][r][c] inside {[-24'sh00_2000:24'sh00_2000]};
                    })
                    `uvm_fatal("RAND", "small-window randomize failed")
            end else begin
                if (!item.randomize())
                    `uvm_fatal("RAND", "randomize failed")
            end

            item.is_last = (i == num_txns - 1);

            start_item(item);
            finish_item(item);
        end
    endtask

endclass
