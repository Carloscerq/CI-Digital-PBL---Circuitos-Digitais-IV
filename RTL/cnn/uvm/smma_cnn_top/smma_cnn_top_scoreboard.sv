// ---------------------------------------------------------------------
//  smma_cnn_top_scoreboard  --  formalizes and extends what
//  tb_smma_cnn_top.sv already checks informally (exactly one
//  m_axis_valid beat per frame with m_axis_last set, printed-not-
//  checked logits), end-to-end through the real 4-stage DUT chain. It
//  deliberately does NOT reimplement the pipeline's math as a golden
//  model -- the sibling per-stage UVM testbenches under RTL/cnn/uvm/
//  (mac_q8_16, line_buffer_3x3, conv2d_fsm, maxpool_2x2,
//  dense_layer_fsm) already verify each stage's arithmetic bit-exact;
//  duplicating that here would just re-check the same math for no real
//  extra confidence. Every item this scoreboard receives is one
//  observed output beat, built by smma_cnn_top_monitor.sv, which has
//  already independently counted the matching input frame's accepted
//  beats and popped it off its FIFO (see that file for the "never
//  early"/"never missing" checks, which live there since they need
//  live interface state this scoreboard doesn't have).
//
//  Per-beat checks:
//   - last          -- must be set (the monitor only forwards accepted
//                       output beats; every one of them must be the
//                       frame's single, final, m_axis_last-carrying
//                       beat -- dense_layer_fsm's ST_OUTPUT always
//                       drives m_last=1, so this also catches any
//                       future change that breaks that).
//   - beats         -- input_beats_accepted must be exactly
//                       IMG_WIDTH*IMG_HEIGHT (1024); this re-affirms,
//                       from the paired-up item, the same invariant the
//                       monitor already checked at the moment the frame
//                       finished streaming.
//   - port breakout -- m_axis_data_normal/unbalance/misalign/bearing
//                       must equal probe_dense[0..3] respectively. Two
//                       ways this could be verified were considered
//                       (see smma_cnn_top_if.sv/smma_cnn_top_uvm_top.sv
//                       for the write-up): a `bind`-based probe, or a
//                       plain hierarchical reference from the new tb
//                       top module into dut.dense_data. The latter was
//                       used -- it needs no extra bind module, is a
//                       single `always_comb` line, and gives exactly
//                       the same visibility. This is a real, cheap
//                       check: the breakout is 4 wire assigns in the
//                       DUT, easy to get an index swapped, and nothing
//                       upstream of it would ever catch that.
//   - not X/Z       -- logits must never be unknown.
//
//  Soft/informational (not counted as failures): whether the 4 logits
//  ever differ from each other -- a real trained model producing 4
//  identical logits every single beat would be a red flag, but it's a
//  heuristic, not a hard protocol invariant, so it's a uvm_warning, not
//  a uvm_error.
// ---------------------------------------------------------------------
class smma_cnn_top_scoreboard extends uvm_subscriber #(smma_cnn_top_seq_item);

    `uvm_component_utils(smma_cnn_top_scoreboard)

    int unsigned n_outputs;
    int unsigned n_last_errors;
    int unsigned n_beatcount_errors;
    int unsigned n_port_mismatch;
    int unsigned n_x_errors;
    int unsigned n_degenerate_warn;

    bit last_ports_match;
    bit last_logits_distinct;

    covergroup result_cg;
        option.per_instance = 1;
        cp_ports: coverpoint last_ports_match {
            bins match    = {1};
            bins mismatch = {0};
        }
        cp_logits: coverpoint last_logits_distinct {
            bins distinct    = {1};
            bins degenerate  = {0};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function void write(smma_cnn_top_seq_item t);
        bit ports_ok;
        bit x_ok;

        n_outputs++;

        if (!t.last) begin
            n_last_errors++;
            `uvm_error("LAST", $sformatf("output beat %0d observed without m_axis_last asserted", n_outputs - 1))
        end

        if (t.input_beats_accepted != NUM_PIXELS) begin
            n_beatcount_errors++;
            `uvm_error("BEATCOUNT",
                $sformatf("output beat %0d: paired input frame had %0d accepted beats (expected %0d)",
                          n_outputs - 1, t.input_beats_accepted, NUM_PIXELS))
        end

        ports_ok = (t.logit_normal    === t.probe_dense[0]) &&
                   (t.logit_unbalance === t.probe_dense[1]) &&
                   (t.logit_misalign  === t.probe_dense[2]) &&
                   (t.logit_bearing   === t.probe_dense[3]);
        if (!ports_ok) begin
            n_port_mismatch++;
            `uvm_error("PORT_BREAKOUT",
                $sformatf("output beat %0d: named ports (%0d,%0d,%0d,%0d) != dense_data[0..3] (%0d,%0d,%0d,%0d)",
                          n_outputs - 1,
                          t.logit_normal, t.logit_unbalance, t.logit_misalign, t.logit_bearing,
                          t.probe_dense[0], t.probe_dense[1], t.probe_dense[2], t.probe_dense[3]))
        end
        last_ports_match = ports_ok;

        x_ok = !($isunknown(t.logit_normal) || $isunknown(t.logit_unbalance) ||
                 $isunknown(t.logit_misalign) || $isunknown(t.logit_bearing));
        if (!x_ok) begin
            n_x_errors++;
            `uvm_error("XCHECK", $sformatf("output beat %0d: one or more logits are X/Z", n_outputs - 1))
        end

        last_logits_distinct = !((t.logit_normal == t.logit_unbalance) &&
                                  (t.logit_normal == t.logit_misalign) &&
                                  (t.logit_normal == t.logit_bearing));
        if (!last_logits_distinct) begin
            n_degenerate_warn++;
            `uvm_warning("DEGENERATE",
                $sformatf("output beat %0d: all 4 logits are identical (%0d) -- unusual for a trained model, not a protocol failure",
                          n_outputs - 1, t.logit_normal))
        end

        result_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("outputs=%0d last_errors=%0d beatcount_errors=%0d port_mismatches=%0d x_errors=%0d degenerate_warnings=%0d",
                      n_outputs, n_last_errors, n_beatcount_errors, n_port_mismatch, n_x_errors, n_degenerate_warn),
            UVM_LOW)
        `uvm_info("SCOREBOARD",
            $sformatf("port-match/logit-distinct covergroup: %0.1f%%", result_cg.get_coverage()), UVM_LOW)

        if (n_outputs == 0)
            `uvm_error("SCOREBOARD", "no output frames were observed")

        if (n_last_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d output beat(s) missing m_axis_last", n_last_errors))

        if (n_beatcount_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d output beat(s) paired with a wrong-length input frame", n_beatcount_errors))

        if (n_port_mismatch != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d output beat(s) had a named-port/dense_data breakout mismatch", n_port_mismatch))

        if (n_x_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d output beat(s) had unknown (X/Z) logits", n_x_errors))
    endfunction

endclass
