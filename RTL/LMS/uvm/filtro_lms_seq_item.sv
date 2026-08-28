// ---------------------------------------------------------------------
//  filtro_lms_seq_item  --  one input sample. Reused for both analysis
//  streams the scoreboard consumes (see filtro_lms_scoreboard.sv), the
//  same way spi_seq_item.sv carries both a "driven intent" side and an
//  "observed" side in one class:
//
//    * the driver publishes one item per accepted sample with only
//      fft_re/fft_im meaningful (the randomized intent a sequence
//      picked, or a directed value) -- got_output/filt_re/filt_im are
//      left at their default/unknown values on this stream.
//
//    * the monitor publishes one item per out_valid pulse with only
//      got_output (always 1'b1 on that stream) and filt_re/filt_im
//      meaningful -- fft_re/fft_im are left at their default values.
//
//  got_output is only ever false for the very first item the scoreboard
//  processes in a run: filtro_lms.v never produces an output for the
//  first sample it ever receives (it only latches x_prev and clears
//  primeira_amostra), so the scoreboard never pairs that item with an
//  observed-output event.
// ---------------------------------------------------------------------
class filtro_lms_seq_item extends uvm_sequence_item;

    rand logic signed [23:0] fft_re;
    rand logic signed [23:0] fft_im;

    bit                  got_output;
    logic signed [23:0]  filt_re;
    logic signed [23:0]  filt_im;

    `uvm_object_utils(filtro_lms_seq_item)

    function new(string name = "filtro_lms_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf(
            "fft_re=%0d fft_im=%0d | got_output=%0b filt_re=%0d filt_im=%0d",
            fft_re, fft_im, got_output, filt_re, filt_im);
    endfunction

    function void do_copy(uvm_object rhs);
        filtro_lms_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to filtro_lms_seq_item failed")
        super.do_copy(rhs);
        fft_re     = rhs_.fft_re;
        fft_im     = rhs_.fft_im;
        got_output = rhs_.got_output;
        filt_re    = rhs_.filt_re;
        filt_im    = rhs_.filt_im;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        filtro_lms_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (fft_re == rhs_.fft_re) && (fft_im == rhs_.fft_im) &&
               (got_output == rhs_.got_output) &&
               (filt_re == rhs_.filt_re) && (filt_im == rhs_.filt_im);
    endfunction

endclass
