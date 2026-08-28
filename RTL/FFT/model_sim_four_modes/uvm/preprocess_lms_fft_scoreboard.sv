// ---------------------------------------------------------------------
//  preprocess_lms_fft_scoreboard  --  the per-beat protocol checks for
//  every accepted fft_valid/fft_ready output beat the monitor forwards
//  (see preprocess_lms_fft_monitor.sv's watch_beats()). This is the
//  single, clearly-identifiable home for the pass/fail assertions that
//  are naturally "per output item" (bin sequencing, X/Z-freedom); the
//  continuous, not-item-shaped checks (saturation/overflow events,
//  pipeline_busy liveness) live directly in the monitor instead, since
//  they need live cycle-by-cycle interface state rather than a
//  per-beat item -- same kind of monitor/scoreboard split
//  smma_cnn_top_monitor.sv/smma_cnn_top_scoreboard.sv use.
//
//  This is deliberately a protocol/integration-level scoreboard, NOT a
//  bit-exact one: reimplementing the FIR/decimation/windowing/FFT math
//  as a golden model to check fft_real/fft_imag's actual numeric
//  values would be a large undertaking that duplicates the existing
//  dataset-driven verification path (tb_fft_lms_dataset.sv, checked
//  against an external Python-computed golden reference) for a first
//  UVM pass that isn't what was asked for -- mirroring the same scope
//  decision made for RTL/cnn/uvm/smma_cnn_top/.
//
//  Per-beat checks:
//   - bin sequencing -- fft_bin must equal the expected next bin
//     (starting at 0, wrapping to 0 immediately after bin 63 -- one
//     frame is exactly 64 beats, bins 0..63 in order, verified against
//     fft_64_dualmode.v's actual S_OUT_READ/S_OUT_WAIT/S_OUT_HOLD
//     output-side FSM: fft_bin_out <= output_count each beat, and
//     output_count counts 0..63 with no gaps/repeats/skips before the
//     FSM moves to S_DONE).
//   - not X/Z -- fft_real/fft_imag must never be unknown on an
//     accepted beat.
//
//  A completed frame is counted every time bin 63 is observed (that's
//  the last bin of a 64-bin frame per the DUT's own output-side
//  contract above). report_phase() below prints the total frame/beat/
//  error counts and flags a no-output-at-all run as an error, but
//  deliberately does NOT assert any *specific* expected frame count --
//  see preprocess_lms_fft_sequences.sv's header for why (cycle-exact
//  latency arithmetic is sidestepped in favor of "however many frames
//  actually complete").
// ---------------------------------------------------------------------
class preprocess_lms_fft_scoreboard extends uvm_subscriber #(preprocess_lms_fft_seq_item);

    `uvm_component_utils(preprocess_lms_fft_scoreboard)

    logic [5:0]  expected_bin;
    int unsigned n_beats;
    int unsigned n_frames;
    int unsigned n_bin_errors;
    int unsigned n_x_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        expected_bin = 6'd0;
    endfunction

    function void write(preprocess_lms_fft_seq_item t);
        bit x_ok;

        n_beats++;

        if (t.fft_bin !== expected_bin) begin
            n_bin_errors++;
            `uvm_error("BINSEQ",
                $sformatf("beat %0d: fft_bin=%0d, expected %0d (bin sweep out of sequence)",
                          n_beats - 1, t.fft_bin, expected_bin))
        end

        x_ok = !($isunknown(t.fft_real) || $isunknown(t.fft_imag));
        if (!x_ok) begin
            n_x_errors++;
            `uvm_error("XCHECK",
                $sformatf("beat %0d (bin %0d): fft_real/fft_imag are X/Z", n_beats - 1, t.fft_bin))
        end

        if (t.fft_bin == 6'd63) begin
            n_frames++;
            expected_bin = 6'd0;
        end else begin
            expected_bin = t.fft_bin + 6'd1;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD",
            $sformatf("beats=%0d frames=%0d bin_errors=%0d x_errors=%0d",
                      n_beats, n_frames, n_bin_errors, n_x_errors), UVM_LOW)

        if (n_frames == 0)
            `uvm_error("SCOREBOARD", "no complete FFT frames (64 bins each) were observed")

        if (n_bin_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d beat(s) had an out-of-sequence fft_bin", n_bin_errors))

        if (n_x_errors != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d beat(s) had unknown (X/Z) fft_real/fft_imag", n_x_errors))
    endfunction

endclass
