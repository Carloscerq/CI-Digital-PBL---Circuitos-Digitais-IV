// ---------------------------------------------------------------------
//  dense_layer_fsm_scoreboard  --  independently reconstructs, from
//  first principles, the exact bit-exact logits dense_layer_fsm.sv
//  should produce for each frame, and checks them against what the DUT
//  actually output -- the real check tb_dense_layer_fsm.sv deliberately
//  stopped short of (its comment: "Removed the hardcoded check ... since
//  we now use real trained weights. We just log the actual ... logits.").
//
//  ROM indexing derivation (verified against dense_layer_fsm.sv's
//  rom_addr/increment_addr/ch logic, cycle by cycle, before committing
//  to this):
//   - rom_addr starts at 0 and increments exactly once per (pixel,
//     channel) tap: once in ST_IDLE when a new pixel is accepted (for
//     channel 0's upcoming fetch) and once more per channel
//     ch < IN_CHANNELS-1 while draining that pixel's channels in
//     ST_MAC. Across a whole frame this sweeps rom_addr 0..IN_FEATURES-1
//     exactly once, in the SAME pixel-major/channel-minor order the
//     features are streamed in.
//   - Tracing the actual read/register timing (rom_data is a
//     synchronous read one cycle behind rom_addr, and captured_data is
//     the pixel latched in ST_IDLE) confirms: at the ST_MAC cycle
//     processing channel ch of pixel pixel_idx, mac_a = captured_data[ch]
//     (== that pixel's s_data[ch] beat) and mac_b = rom_data[neuron],
//     which was fetched using rom_addr == pixel_idx*IN_CHANNELS + ch.
//     So feature index f = pixel_idx*IN_CHANNELS + ch corresponds to
//     rom_array[neuron*IN_FEATURES + f] for the weight, and to the
//     pixel_idx'th streamed beat's s_data[ch] for the activation --
//     exactly the indexing this scoreboard implements below.
//   - The bias tap (ST_ADD_BIAS: mac_a=biases[neuron],
//     mac_b=1<<FRAC_BITS) is proven (by tracing mac_q8_16's 2-cycle
//     a/b->mult->acc pipeline against the FSM's 2-cycle ST_WAIT) to be
//     the LAST product folded into acc_reg before ST_OUTPUT freezes the
//     pipeline (mac_en drops to 0) -- the stale captured_data[ch]/
//     rom_data[neuron] values combinationally present during ST_WAIT
//     (mac_en stays high there "to allow the pipeline to progress") are
//     loaded into the a/b registers but never reach mult_reg+acc_reg
//     before en drops, so they never contaminate the sum. This confirms
//     ST_WAIT's 2 cycles are exactly (and only) the drain time the bias
//     tap needs, and the golden sum below is exactly the 2048 dot-product
//     taps plus one bias tap, nothing else.
//
//  Golden per-neuron computation (compute_acc()):
//    acc = sum_{p=0..NUM_PIXELS-1, ch=0..IN_CHANNELS-1}
//              longint'(pixels[p][ch]) * longint'(rom_array[neuron*IN_FEATURES + p*IN_CHANNELS + ch])
//        + longint'(biases[neuron]) * longint'(1 <<< FRAC_BITS)
//  computed in a 64-bit longint (comfortably wide: |acc| bounded by
//  roughly NUM_PIXELS*IN_CHANNELS * 2^(2*(DATA_WIDTH-1)) ~ 2^57, well
//  under the 64-bit signed range), then reduced to mac_q8_16's real
//  48-bit (ACC_W = 2*DATA_WIDTH) accumulator width via truncating
//  part-select -- this reproduces two's-complement wraparound exactly
//  as the physical acc_reg register would experience it even if an
//  intermediate partial sum momentarily overflowed 48 bits (modular
//  arithmetic is associative, so only the FINAL 48-bit residue matters).
//  apply_mac_saturate() then reimplements mac_q8_16.sv's truncate +
//  overflow/underflow + saturate logic bit-for-bit. No ReLU is applied
//  at the dense output (unlike conv2d_fsm) -- the saturated mac_out IS
//  the final logit.
//
//  Weights/biases are loaded via the SAME $readmemh calls (same
//  relative paths, same CWD=RTL/ requirement) the DUT itself uses, so
//  this is a genuine independent recomputation from the real trained
//  network, not a re-derivation of whatever the DUT happened to output.
//
//  Frames are matched to results by their arrival order in a queue
//  (expected_q): write_frame() computes and pushes one frame's expected
//  logits immediately (the ROM is already loaded by then), write_result()
//  pops the oldest pending entry and compares. Since the driver streams
//  one frame fully (and waits for item_done) before starting the next,
//  and the DUT only ever has one frame in flight, this queue is never
//  more than one entry deep in practice -- but using a queue rather than
//  a single "current frame" register keeps the scoreboard correct even
//  if that assumption ever changes.
//
//  Covergroup: a single "any neuron saturated this frame" bin
//  (hit/no-hit), the simplified alternative the task explicitly allows
//  over 4 separate per-neuron bins -- simpler to reason about and
//  sufficient to confirm the saturation path in apply_mac_saturate() (and
//  therefore in mac_q8_16.sv) actually gets exercised by the randomized
//  frames.
// ---------------------------------------------------------------------

`uvm_analysis_imp_decl(_frame)
`uvm_analysis_imp_decl(_result)

class dense_layer_fsm_scoreboard extends uvm_component;

    `uvm_component_utils(dense_layer_fsm_scoreboard)

    uvm_analysis_imp_frame  #(dense_layer_fsm_seq_item,    dense_layer_fsm_scoreboard) frame_export;
    uvm_analysis_imp_result #(dense_layer_fsm_result_item, dense_layer_fsm_scoreboard) result_export;

    // Weight ROM / bias memory, loaded from the same .mem files the DUT
    // reads, independently of the DUT's own copies.
    logic signed [DATA_WIDTH-1:0] rom_array [0:(OUT_CLASSES * IN_FEATURES) - 1];
    logic signed [DATA_WIDTH-1:0] biases    [0:OUT_CLASSES-1];

    typedef struct {
        logic signed [DATA_WIDTH-1:0] logits [OUT_CLASSES];
    } expected_t;

    expected_t expected_q [$];

    int unsigned frame_count;
    int unsigned result_count;
    int unsigned mismatch_frames;
    int unsigned mismatch_logits;
    int unsigned last_errors;
    int unsigned saturating_frames;
    int unsigned non_saturating_frames;

    bit any_saturated_sample;

    covergroup result_cg;
        option.per_instance = 1;
        cp_sat: coverpoint any_saturated_sample {
            bins hit    = {1};
            bins no_hit = {0};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        frame_export  = new("frame_export", this);
        result_export = new("result_export", this);

        // Same relative paths and CWD=RTL/ requirement as
        // dense_layer_fsm.sv's own $readmemh calls.
        $readmemh("mem/cnn/dense_weights.mem", rom_array);
        $readmemh("mem/cnn/dense_biases.mem", biases);
        `uvm_info("SCOREBOARD", "loaded dense_weights.mem / dense_biases.mem for golden-model computation", UVM_LOW)
    endfunction

    // Reimplements mac_q8_16.sv's combinational truncate + saturate
    // logic bit-for-bit against a 48-bit (ACC_W = 2*DATA_WIDTH)
    // accumulator value.
    function automatic logic signed [DATA_WIDTH-1:0] apply_mac_saturate(
        input logic signed [(2*DATA_WIDTH)-1:0] acc_w,
        output bit saturated
    );
        logic signed [DATA_WIDTH-1:0] truncated_out;
        bit overflow, underflow;

        truncated_out = acc_w[FRAC_BITS + DATA_WIDTH - 1 : FRAC_BITS];

        if (!acc_w[(2*DATA_WIDTH)-1] && (|acc_w[(2*DATA_WIDTH)-2 : FRAC_BITS + DATA_WIDTH - 1])) begin
            overflow  = 1'b1;
            underflow = 1'b0;
        end else if (acc_w[(2*DATA_WIDTH)-1] && (!(&acc_w[(2*DATA_WIDTH)-2 : FRAC_BITS + DATA_WIDTH - 1]))) begin
            overflow  = 1'b0;
            underflow = 1'b1;
        end else begin
            overflow  = 1'b0;
            underflow = 1'b0;
        end

        saturated = overflow || underflow;

        if (overflow)
            return {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else if (underflow)
            return {1'b1, {(DATA_WIDTH-1){1'b0}}};
        else
            return truncated_out;
    endfunction

    // Golden dot product + bias for one output neuron, using the
    // pixel-major/channel-minor feature indexing derived above.
    function automatic longint signed compute_acc(dense_layer_fsm_seq_item t, int neuron);
        longint signed acc;
        acc = 0;
        for (int p = 0; p < NUM_PIXELS; p++) begin
            for (int ch = 0; ch < IN_CHANNELS; ch++) begin
                acc += longint'(t.pixels[p][ch]) *
                       longint'(rom_array[neuron * IN_FEATURES + p * IN_CHANNELS + ch]);
            end
        end
        acc += longint'(biases[neuron]) * (longint'(1) <<< FRAC_BITS);
        return acc;
    endfunction

    // --- driver's ground-truth frame -----------------------------------
    function void write_frame(dense_layer_fsm_seq_item t);
        expected_t exp;
        bit sat;
        bit frame_sat;

        frame_sat = 1'b0;
        for (int neuron = 0; neuron < OUT_CLASSES; neuron++) begin
            longint signed acc_full;
            logic signed [(2*DATA_WIDTH)-1:0] acc_w;

            acc_full = compute_acc(t, neuron);
            acc_w    = acc_full[(2*DATA_WIDTH)-1:0]; // wrap to the real 48-bit accumulator width

            exp.logits[neuron] = apply_mac_saturate(acc_w, sat);
            if (sat) frame_sat = 1'b1;
        end

        expected_q.push_back(exp);
        frame_count++;

        any_saturated_sample = frame_sat;
        result_cg.sample();
        if (frame_sat) saturating_frames++;
        else            non_saturating_frames++;
    endfunction

    // --- monitor's observed output beat --------------------------------
    function void write_result(dense_layer_fsm_result_item t);
        expected_t exp;
        bit ok;

        if (expected_q.size() == 0)
            `uvm_fatal("NOFRAME", "received an output beat before any frame was published by the driver")

        exp = expected_q.pop_front();
        result_count++;
        ok = 1'b1;

        for (int neuron = 0; neuron < OUT_CLASSES; neuron++) begin
            if (t.logits[neuron] !== exp.logits[neuron]) begin
                `uvm_error("LOGIT", $sformatf("frame %0d neuron %0d: expected %0d (0x%0h), got %0d (0x%0h)",
                           result_count-1, neuron,
                           exp.logits[neuron], exp.logits[neuron],
                           t.logits[neuron], t.logits[neuron]))
                mismatch_logits++;
                ok = 1'b0;
            end
        end
        if (!ok) mismatch_frames++;

        if (!t.last) begin
            `uvm_error("LAST", $sformatf("frame %0d: m_last was not asserted alongside the dense output beat", result_count-1))
            last_errors++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("frames=%0d results=%0d mismatched_frames=%0d mismatched_logits=%0d last_errors=%0d",
                      frame_count, result_count, mismatch_frames, mismatch_logits, last_errors), UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("saturating_frames=%0d non_saturating_frames=%0d saturation coverage=%0.1f%%",
                      saturating_frames, non_saturating_frames, result_cg.get_coverage()), UVM_LOW)

        if (frame_count == 0)
            `uvm_error("SCOREBOARD", "no frames were observed")

        if (result_count != frame_count)
            `uvm_error("SCOREBOARD", $sformatf("result_count %0d != frame_count %0d", result_count, frame_count))

        if (mismatch_frames != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d of %0d frames mismatched the golden bit-exact reconstruction",
                                                mismatch_frames, result_count))

        if (last_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d m_last placement errors", last_errors))
    endfunction

endclass
