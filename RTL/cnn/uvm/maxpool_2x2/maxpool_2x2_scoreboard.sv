// ---------------------------------------------------------------------
//  maxpool_2x2_scoreboard  --  independently reconstructs, from first
//  principles, what every one of the NUM_OUT (256) pooled outputs per
//  frame should be, and checks EVERY one against what the DUT actually
//  produced -- unlike tb_maxpool_2x2.sv's monitor_pool(), which only
//  gets away with a closed-form expected value because its stimulus
//  pattern is monotonically increasing in raster order (so the max of
//  every 2x2 block is trivially its bottom-right pixel). Here the
//  expected value is a genuine max of 4 arbitrary values per channel,
//  computed straight from the pixel array the driver actually streamed
//  -- meaningful even for maxpool_2x2_random_seq's non-monotonic,
//  occasionally-tied content.
//
//  Frame bookkeeping uses a QUEUE of pixel frames rather than a single
//  "current frame" variable. Reason: the driver publishes frame N+1 on
//  frame_ap the instant it dequeues the next sequence item, which can
//  happen right after frame N's very last input pixel is accepted --
//  but the DUT's pipeline (registered output, s_ready = m_ready ||
//  !m_valid_reg) means frame N's *last* pooled output may still be sat
//  behind monitor-applied m_ready backpressure at that exact moment.
//  A single-frame variable would risk the tail output of frame N being
//  checked against frame N+1's pixels. Queueing sidesteps this
//  entirely: write_frame() pushes to the back, write_out() always reads
//  from the front, and only pops the front once that frame's NUM_OUT-th
//  output (tracked by exp_idx below, not merely trusted from the
//  monitor) has been consumed -- correct regardless of how much
//  pipeline/backpressure latency separates "last pixel in" from "last
//  pooled output out".
//
//  win_idx (0-based position within the pooled grid of the *current*
//  frame) is provided by the monitor, but exp_idx here is the
//  scoreboard's own independently-maintained counter, cross-checked
//  against it -- so a monitor bug in win_idx bookkeeping would itself
//  surface as a scoreboard error rather than silently mis-indexing.
//
//  Covergroup: win_pos classifies which corner of the 2x2 block (top-
//  left / top-right / bottom-left / bottom-right) held the unique
//  maximum for a given (output, channel) sample, or "tied" when two or
//  more corners equal the maximum -- giving visibility into whether the
//  DUT's cascaded-comparator tie-breaking path (ties don't change the
//  numeric result, since tied values are equal, but they're the
//  trickiest case for a comparator tree to get right) actually got
//  exercised. maxpool_2x2_random_seq deliberately manufactures some tied
//  blocks so this bin isn't left empty.
// ---------------------------------------------------------------------

`uvm_analysis_imp_decl(_frame)
`uvm_analysis_imp_decl(_out)

class maxpool_2x2_scoreboard extends uvm_component;

    `uvm_component_utils(maxpool_2x2_scoreboard)

    uvm_analysis_imp_frame #(maxpool_2x2_seq_item, maxpool_2x2_scoreboard) frame_export;
    uvm_analysis_imp_out   #(maxpool_2x2_out_item, maxpool_2x2_scoreboard) out_export;

    typedef logic signed [DATA_WIDTH-1:0] pixel_frame_t [IMG_WIDTH][IMG_WIDTH][CHANNELS];
    pixel_frame_t frame_q [$];

    int unsigned exp_idx;          // 0..NUM_OUT-1 within the frame at the front of frame_q
    int unsigned frame_count;
    int unsigned total_outputs;
    int unsigned mismatch_outputs;
    int unsigned mismatch_elems;
    int unsigned last_errors;
    int unsigned idx_errors;
    int unsigned tie_samples;
    int unsigned unique_samples;

    // Declared ahead of pos_cg so the covergroup's coverpoint expression
    // resolves (Xcelium: an in-class covergroup coverpoint must reference
    // a class member declared earlier in the class body).
    typedef enum {POS_TL, POS_TR, POS_BL, POS_BR, POS_TIE} max_pos_e;
    max_pos_e win_pos;

    covergroup pos_cg;
        option.per_instance = 1;
        cp_pos: coverpoint win_pos {
            bins top_left    = {POS_TL};
            bins top_right   = {POS_TR};
            bins bottom_left = {POS_BL};
            bins bottom_right = {POS_BR};
            bins tied        = {POS_TIE};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        pos_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        frame_export = new("frame_export", this);
        out_export   = new("out_export", this);
    endfunction

    // --- driver's ground-truth frame -----------------------------------
    function void write_frame(maxpool_2x2_seq_item t);
        frame_q.push_back(t.pixels);
        frame_count++;
    endfunction

    // --- monitor's observed pooled output --------------------------------
    function void write_out(maxpool_2x2_out_item t);
        pixel_frame_t cur;
        int r_out, c_out, r0, c0;
        logic signed [DATA_WIDTH-1:0] expected [CHANNELS];
        bit out_ok;

        if (frame_q.size() == 0)
            `uvm_fatal("NOFRAME", "received a pooled output before any frame was published by the driver")

        if (t.win_idx != exp_idx) begin
            `uvm_error("IDX", $sformatf("frame %0d: monitor win_idx=%0d but scoreboard expected %0d",
                        frame_count - frame_q.size() + 1, t.win_idx, exp_idx))
            idx_errors++;
        end

        cur = frame_q[0];

        r_out = exp_idx / OUT_WIDTH;
        c_out = exp_idx % OUT_WIDTH;
        r0 = r_out * 2;
        c0 = c_out * 2;

        out_ok = 1'b1;
        for (int ch = 0; ch < CHANNELS; ch++) begin
            logic signed [DATA_WIDTH-1:0] tl, tr, bl, br, mx;
            int unsigned win_count;

            tl = cur[r0][c0][ch];
            tr = cur[r0][c0+1][ch];
            bl = cur[r0+1][c0][ch];
            br = cur[r0+1][c0+1][ch];

            mx = tl;
            if (tr > mx) mx = tr;
            if (bl > mx) mx = bl;
            if (br > mx) mx = br;
            expected[ch] = mx;

            if (t.data[ch] !== expected[ch]) begin
                `uvm_error("MAXPOOL", $sformatf(
                    "out %0d (r_out=%0d,c_out=%0d) ch=%0d: expected %0d, got %0d",
                    exp_idx, r_out, c_out, ch, expected[ch], t.data[ch]))
                mismatch_elems++;
                out_ok = 1'b0;
            end

            win_count = (tl == mx) + (tr == mx) + (bl == mx) + (br == mx);
            if (win_count > 1) begin
                win_pos = POS_TIE;
                tie_samples++;
            end else begin
                if (tl == mx)      win_pos = POS_TL;
                else if (tr == mx) win_pos = POS_TR;
                else if (bl == mx) win_pos = POS_BL;
                else                win_pos = POS_BR;
                unique_samples++;
            end
            pos_cg.sample();
        end

        if (!out_ok) mismatch_outputs++;
        total_outputs++;

        if (exp_idx == NUM_OUT - 1) begin
            if (!t.last) begin
                `uvm_error("LAST", $sformatf("output %0d is the last output of its frame but m_last was not asserted", exp_idx))
                last_errors++;
            end
            void'(frame_q.pop_front());
            exp_idx = 0;
        end else begin
            if (t.last) begin
                `uvm_error("LAST", $sformatf("m_last asserted at output %0d (expected at %0d)", exp_idx, NUM_OUT - 1))
                last_errors++;
            end
            exp_idx++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("frames=%0d total_outputs=%0d mismatched_outputs=%0d mismatched_elements=%0d last_errors=%0d idx_errors=%0d",
                      frame_count, total_outputs, mismatch_outputs, mismatch_elems, last_errors, idx_errors), UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("unique_max_samples=%0d tied_max_samples=%0d winning-corner coverage=%0.1f%%",
                      unique_samples, tie_samples, pos_cg.get_coverage()), UVM_LOW)

        if (frame_count == 0)
            `uvm_error("SCOREBOARD", "no frames were observed")

        if (mismatch_outputs != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d of %0d outputs mismatched the golden max-of-4 reconstruction",
                                                mismatch_outputs, total_outputs))

        if (last_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d m_last placement errors", last_errors))

        if (idx_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d win_idx bookkeeping mismatches", idx_errors))

        if (frame_q.size() != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d frame(s) published but never fully drained through the output side", frame_q.size()))

        if ((total_outputs != 0) && (frame_count != 0) && (total_outputs != frame_count * NUM_OUT))
            `uvm_error("SCOREBOARD", $sformatf("total output count %0d != frame_count(%0d) * NUM_OUT(%0d)",
                                                total_outputs, frame_count, NUM_OUT))
    endfunction

endclass
