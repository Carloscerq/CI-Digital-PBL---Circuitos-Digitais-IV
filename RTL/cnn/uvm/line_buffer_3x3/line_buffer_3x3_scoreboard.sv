// ---------------------------------------------------------------------
//  line_buffer_3x3_scoreboard  --  independently reconstructs, from
//  first principles, what every one of the 1024 output windows per
//  frame should be, and checks EVERY one against what the DUT actually
//  produced -- unlike tb_line_buffer_3x3.sv's monitor_output(), which
//  only rigorously checks the very first window and then just waves the
//  remaining 1023 through as long as the count and m_last line up. That
//  first-window-only check is real coverage this testbench closes.
//
//  How the reconstruction works:
//   - write_frame() (fed by the driver's frame_ap, once per frame,
//     published the instant the driver starts streaming) builds a
//     zero-padded (IMG_HEIGHT+2) x (IMG_WIDTH+2) x IN_CHANNELS golden
//     buffer: a 1-pixel zero border around the frame's real pixels,
//     exactly the padded grid line_buffer_3x3.sv walks internally.
//   - write_win() (fed by the monitor's ap, once per accepted output
//     window) tracks a raster window index 0..1023 within the current
//     frame. Window index W corresponds to real-image position
//     (r,c) = (W / IMG_WIDTH, W % IMG_WIDTH), which the DUT centers at
//     padded coordinate (r+1, c+1); its 3x3 neighbourhood is therefore
//     padded[r .. r+2][c .. c+2] -- read directly out of the golden
//     buffer built above, with no dependency on anything the DUT did.
//     Every channel/row/col of that window is compared to the DUT's
//     actual output.
//
//  Total window count (1024 per frame) and m_last placement (asserted
//  on window 1024 and only window 1024) are checked the same way the
//  original tb checks them, just generalized to work across multiple
//  frames back-to-back.
//
//  Covergroup bins split windows into "edge" (touch the zero padding:
//  real row/col 0 or IMG_HEIGHT-1/IMG_WIDTH-1) vs "interior" (fully
//  surrounded by real pixels) -- the edge case is where zero
//  substitution actually happens and is the trickiest to get right.
// ---------------------------------------------------------------------

`uvm_analysis_imp_decl(_frame)
`uvm_analysis_imp_decl(_win)

class line_buffer_3x3_scoreboard extends uvm_component;

    `uvm_component_utils(line_buffer_3x3_scoreboard)

    uvm_analysis_imp_frame #(line_buffer_3x3_seq_item, line_buffer_3x3_scoreboard) frame_export;
    uvm_analysis_imp_win   #(line_buffer_3x3_window_item, line_buffer_3x3_scoreboard) win_export;

    // Zero-padded golden frame: padded[py][px][ch], py in 0..PAD_HEIGHT-1,
    // px in 0..PAD_WIDTH-1. padded[1+r][1+c][ch] == pixels[r][c][ch];
    // every border row/col is zero.
    logic signed [DATA_WIDTH-1:0] padded [PAD_HEIGHT][PAD_WIDTH][IN_CHANNELS];
    bit have_frame = 0;

    int unsigned window_idx;       // 0..NUM_PIXELS-1 within the current frame
    int unsigned frame_count;
    int unsigned total_windows;
    int unsigned mismatch_windows;
    int unsigned mismatch_elems;
    int unsigned last_errors;
    int unsigned edge_windows;
    int unsigned interior_windows;

    bit is_edge_sample;

    covergroup win_cg;
        option.per_instance = 1;
        cp_edge: coverpoint is_edge_sample {
            bins border   = {1};
            bins interior = {0};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        win_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        frame_export = new("frame_export", this);
        win_export   = new("win_export", this);
    endfunction

    // --- driver's ground-truth frame -----------------------------------
    function void write_frame(line_buffer_3x3_seq_item t);
        for (int py = 0; py < PAD_HEIGHT; py++) begin
            for (int px = 0; px < PAD_WIDTH; px++) begin
                for (int ch = 0; ch < IN_CHANNELS; ch++) begin
                    if (py == 0 || py == PAD_HEIGHT - 1 || px == 0 || px == PAD_WIDTH - 1)
                        padded[py][px][ch] = '0;
                    else
                        padded[py][px][ch] = t.pixels[py-1][px-1][ch];
                end
            end
        end
        have_frame  = 1;
        window_idx  = 0;
        frame_count++;
    endfunction

    // --- monitor's observed output window --------------------------------
    function void write_win(line_buffer_3x3_window_item t);
        logic signed [DATA_WIDTH-1:0] expected [IN_CHANNELS][3][3];
        int r, c;
        bit win_ok;

        if (!have_frame)
            `uvm_fatal("NOFRAME", "received an output window before any frame was published by the driver")

        r = window_idx / IMG_WIDTH;
        c = window_idx % IMG_WIDTH;

        win_ok = 1'b1;
        for (int ch = 0; ch < IN_CHANNELS; ch++) begin
            for (int i = 0; i < 3; i++) begin
                for (int j = 0; j < 3; j++) begin
                    expected[ch][i][j] = padded[r+i][c+j][ch];
                    if (t.window[ch][i][j] !== expected[ch][i][j]) begin
                        `uvm_error("WINDOW",
                            $sformatf("frame %0d window %0d (r=%0d,c=%0d) ch=%0d [%0d][%0d]: expected %0d, got %0d",
                                      frame_count, window_idx, r, c, ch, i, j,
                                      expected[ch][i][j], t.window[ch][i][j]))
                        mismatch_elems++;
                        win_ok = 1'b0;
                    end
                end
            end
        end
        if (!win_ok) mismatch_windows++;

        is_edge_sample = (r == 0) || (r == IMG_HEIGHT - 1) || (c == 0) || (c == IMG_WIDTH - 1);
        win_cg.sample();
        if (is_edge_sample) edge_windows++;
        else                interior_windows++;

        total_windows++;
        window_idx++;

        if (t.last) begin
            if (window_idx != NUM_PIXELS) begin
                `uvm_error("LAST", $sformatf("m_last asserted at window %0d of frame %0d (expected %0d)",
                                              window_idx, frame_count, NUM_PIXELS))
                last_errors++;
            end
        end else begin
            if (window_idx == NUM_PIXELS) begin
                `uvm_error("LAST", $sformatf("window %0d of frame %0d is the last window of the frame but m_last was not asserted",
                                              window_idx, frame_count))
                last_errors++;
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("frames=%0d total_windows=%0d mismatched_windows=%0d mismatched_elements=%0d last_errors=%0d",
                      frame_count, total_windows, mismatch_windows, mismatch_elems, last_errors), UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("edge_windows=%0d interior_windows=%0d edge/interior coverage=%0.1f%%",
                      edge_windows, interior_windows, win_cg.get_coverage()), UVM_LOW)

        if (frame_count == 0)
            `uvm_error("SCOREBOARD", "no frames were observed")

        if (mismatch_windows != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d of %0d windows mismatched the golden zero-padded reconstruction",
                                                mismatch_windows, total_windows))

        if (last_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d m_last placement errors", last_errors))

        if ((total_windows != 0) && (frame_count != 0) && (total_windows != frame_count * NUM_PIXELS))
            `uvm_error("SCOREBOARD", $sformatf("total window count %0d != frame_count(%0d) * NUM_PIXELS(%0d)",
                                                total_windows, frame_count, NUM_PIXELS))
    endfunction

endclass
