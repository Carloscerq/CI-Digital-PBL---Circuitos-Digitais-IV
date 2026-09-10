// ---------------------------------------------------------------------
//  preprocess_lms_fft_seq_item  --  one item = one desired_sample beat
//  (the DUT's slave-side handshake granularity), matching the "one item
//  = one protocol-level unit" convention used across this repo's UVM
//  testbenches, just at beat rather than frame granularity here (unlike
//  cnn_top_seq_item, which is one item per whole 1024-pixel
//  frame -- the FFT pipeline's input side has no natural "frame"
//  boundary from the driver's point of view, only the 32:1-decimated/
//  64-sample-hop framing happening deep inside the DUT).
//
//  This item does double duty, the same split cnn_top_seq_item
//  uses:
//   - `desired_sample` is the randomized/directed stimulus the driver
//     streams in (see preprocess_lms_fft_driver.sv and
//     preprocess_lms_fft_sequences.sv);
//   - the fft_bin/fft_real/fft_imag fields are NOT randomized -- left
//     at their default (0) on driven items, and instead filled in on a
//     *separate* item instance created by the monitor for each accepted
//     fft_valid/fft_ready output beat (see
//     preprocess_lms_fft_monitor.sv), then consumed by
//     preprocess_lms_fft_scoreboard.sv.
//
//  c_modest_amplitude bounds the randomizable range well inside the
//  full 24-bit signed range (+-8,388,608) so that IF this class is ever
//  randomize()'d directly (the primary directed sequence computes
//  desired_sample procedurally and does not call randomize()), the
//  "no spurious saturation/overflow event fires" scoreboard check
//  in preprocess_lms_fft_monitor.sv stays meaningful rather than
//  vacuous.
// ---------------------------------------------------------------------
class preprocess_lms_fft_seq_item extends uvm_sequence_item;

    rand logic signed [DATA_WIDTH-1:0] desired_sample;

    // --- result fields, filled in by the monitor for each accepted
    //     fft_valid/fft_ready beat -- not part of the driven stimulus,
    //     see class header above ---
    logic [5:0]                    fft_bin;
    logic signed [DATA_WIDTH-1:0]  fft_real;
    logic signed [DATA_WIDTH-1:0]  fft_imag;

    constraint c_modest_amplitude {
        desired_sample inside {[-24'sd100000 : 24'sd100000]};
    }

    `uvm_object_utils(preprocess_lms_fft_seq_item)

    function new(string name = "preprocess_lms_fft_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("preprocess_lms_fft_seq_item: desired_sample=%0d | fft_bin=%0d fft_real=%0d fft_imag=%0d",
                          desired_sample, fft_bin, fft_real, fft_imag);
    endfunction

    function void do_copy(uvm_object rhs);
        preprocess_lms_fft_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to preprocess_lms_fft_seq_item failed")
        super.do_copy(rhs);
        desired_sample = rhs_.desired_sample;
        fft_bin        = rhs_.fft_bin;
        fft_real       = rhs_.fft_real;
        fft_imag       = rhs_.fft_imag;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        preprocess_lms_fft_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (desired_sample == rhs_.desired_sample) &&
               (fft_bin        == rhs_.fft_bin) &&
               (fft_real       == rhs_.fft_real) &&
               (fft_imag       == rhs_.fft_imag);
    endfunction

endclass
