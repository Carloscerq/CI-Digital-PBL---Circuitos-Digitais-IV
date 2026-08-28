// ---------------------------------------------------------------------
//  filtro_lms_scoreboard  --  self-checking golden model built directly
//  from filtro_lms.v's FSM (see filtro_lms.v's per-state assignments:
//  MULT_Y/CALC_Y, CALC_ERRO, MULT_GRAD/CALC_GRAD, MULT_MU/ATUALIZA).
//  Unlike a stateless per-item golden function, this DUT is genuinely
//  stateful: the complex tap weight `w` and the previous input sample
//  `x_prev` persist and evolve across the whole stream, so this
//  scoreboard keeps its own shadow copy of (w_re, w_im, x_prev_re,
//  x_prev_im, primeira_amostra), advanced in lockstep with every driven
//  sample -- not just the ones that produce an output.
//
//  Two independent analysis streams are paired here exactly the way
//  spi_scoreboard.sv pairs spi_driver.ap against spi_monitor.ap:
//
//    driven_export   -- one item per accepted input sample, in order
//                        (filtro_lms_driver.sv, published immediately
//                        after driving it).
//    observed_export -- one item per out_valid pulse, in arrival order
//                        (filtro_lms_monitor.sv).
//
//  Since the DUT fully finishes one sample (through FINALIZA back to
//  IDLE) before in_ready reasserts for the next, there is no pipelining
//  to reason about here: driven order and produced-output order are
//  strictly 1:1, offset by exactly one "no output" first sample. So the
//  golden expected output for each non-first driven sample is computed
//  and queued the moment that sample is processed (write_driven), and
//  popped/compared the moment the matching out_valid event arrives
//  (write_observed).
// ---------------------------------------------------------------------
class filtro_lms_scoreboard extends uvm_component;

    `uvm_component_utils(filtro_lms_scoreboard)

    uvm_analysis_imp_driven   #(filtro_lms_seq_item, filtro_lms_scoreboard) driven_export;
    uvm_analysis_imp_observed #(filtro_lms_seq_item, filtro_lms_scoreboard) observed_export;

    // matches filtro_lms.v's default MU parameter (tb/filtro_lms_uvm_top.sv
    // instantiates the DUT with its default too)
    localparam logic signed [23:0] MU = 24'sd1638;

    localparam longint signed SAT_MAX = 64'sd8388607;
    localparam longint signed SAT_MIN = -64'sd8388608;

    // -- shadow reference state, mirrors filtro_lms.v's own w_re/w_im/
    // x_prev_re/x_prev_im/primeira_amostra registers, reset the same way
    // (all zero, primeira_amostra true) --
    logic signed [23:0] w_re              = 24'sd0;
    logic signed [23:0] w_im              = 24'sd0;
    logic signed [23:0] x_prev_re         = 24'sd0;
    logic signed [23:0] x_prev_im         = 24'sd0;
    bit                 primeira_amostra  = 1'b1;

    // golden outputs computed by write_driven(), waiting to be paired
    // with an observed out_valid event by write_observed()
    logic signed [23:0] exp_re_q [$];
    logic signed [23:0] exp_im_q [$];

    // independently-observed out_valid events, waiting to be paired
    filtro_lms_seq_item observed_q [$];

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    // sampled once per non-first driven sample (i.e. once per golden
    // computation), true if ANY of the 5 saturation points (step1 re/im,
    // step2 re/im, step3 re/im, step4 re/im, step5 re/im) clamped
    bit last_any_saturation;

    covergroup sat_cg;
        option.per_instance = 1;
        cp_sat: coverpoint last_any_saturation {
            bins none = {1'b0};
            bins hit  = {1'b1};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        driven_export   = new("driven_export", this);
        observed_export = new("observed_export", this);
        sat_cg = new();
    endfunction

    // clips a wide signed accumulator to the DUT's 24-bit signed range,
    // exactly the way every saturation point in filtro_lms.v does
    // (`if (v > 24'sd8388607) ... else if (v < -24'sd8388608) ...`),
    // regardless of the intermediate register's own width.
    function automatic logic signed [23:0] sat24(longint signed val, output bit saturated);
        if (val > SAT_MAX) begin
            saturated = 1'b1;
            return 24'sh7FFFFF;
        end else if (val < SAT_MIN) begin
            saturated = 1'b1;
            return 24'sh800000;
        end else begin
            saturated = 1'b0;
            return 24'(val);
        end
    endfunction

    function void write_driven(filtro_lms_seq_item t);
        longint signed mult1, mult2, mult3, mult4;
        longint signed sum_re, sum_im;
        logic signed [23:0] y_re, y_im, e_re, e_im, grad_re, grad_im;
        logic signed [23:0] delta_w_re, delta_w_im, w_re_new, w_im_new;
        bit s1re, s1im, s2re, s2im, s3re, s3im, s4re, s4im, s5re, s5im;

        if (primeira_amostra) begin
            // RECEBE with primeira_amostra set: only x_prev is latched
            // and the flag cleared -- the FSM jumps straight to
            // FINALIZA, out_valid never pulses for this sample.
            x_prev_re = t.fft_re;
            x_prev_im = t.fft_im;
            primeira_amostra = 1'b0;
            return;
        end

        // step 1 (MULT_Y/CALC_Y): y = Q15-scaled complex multiply of the
        // carried-over w and x_prev
        mult1  = longint'(w_re) * longint'(x_prev_re);
        mult2  = longint'(w_im) * longint'(x_prev_im);
        mult3  = longint'(w_re) * longint'(x_prev_im);
        mult4  = longint'(w_im) * longint'(x_prev_re);
        sum_re = mult1 - mult2;
        sum_im = mult3 + mult4;
        y_re = sat24(sum_re >>> 15, s1re);
        y_im = sat24(sum_im >>> 15, s1im);

        // step 2 (CALC_ERRO): e = d - y
        e_re = sat24(longint'(t.fft_re) - longint'(y_re), s2re);
        e_im = sat24(longint'(t.fft_im) - longint'(y_im), s2im);

        // step 3 (MULT_GRAD/CALC_GRAD): grad = Q15-scaled complex
        // multiply of e and conj(x_prev)
        mult1  = longint'(e_re) * longint'(x_prev_re);
        mult2  = longint'(e_im) * longint'(x_prev_im);
        mult3  = longint'(e_im) * longint'(x_prev_re);
        mult4  = longint'(e_re) * longint'(x_prev_im);
        sum_re = mult1 + mult2;
        sum_im = mult3 - mult4;
        grad_re = sat24(sum_re >>> 15, s3re);
        grad_im = sat24(sum_im >>> 15, s3im);

        // step 4 (MULT_MU/ATUALIZA): delta_w = Q15-scaled MU*grad
        delta_w_re = sat24((longint'(MU) * longint'(grad_re)) >>> 15, s4re);
        delta_w_im = sat24((longint'(MU) * longint'(grad_im)) >>> 15, s4im);

        // step 5 (ATUALIZA): weight update
        w_re_new = sat24(longint'(w_re) + longint'(delta_w_re), s5re);
        w_im_new = sat24(longint'(w_im) + longint'(delta_w_im), s5im);

        last_any_saturation = s1re | s1im | s2re | s2im | s3re | s3im | s4re | s4im | s5re | s5im;
        sat_cg.sample();

        exp_re_q.push_back(y_re);
        exp_im_q.push_back(y_im);

        // state carried into the NEXT sample, exactly as ATUALIZA does
        w_re      = w_re_new;
        w_im      = w_im_new;
        x_prev_re = t.fft_re;
        x_prev_im = t.fft_im;

        try_compare();
    endfunction

    function void write_observed(filtro_lms_seq_item t);
        filtro_lms_seq_item t_;
        $cast(t_, t.clone());
        observed_q.push_back(t_);
        try_compare();
    endfunction

    function void try_compare();
        logic signed [23:0] exp_re, exp_im;
        filtro_lms_seq_item obs;

        while (exp_re_q.size() > 0 && observed_q.size() > 0) begin
            exp_re = exp_re_q.pop_front();
            exp_im = exp_im_q.pop_front();
            obs    = observed_q.pop_front();

            if ((obs.filt_re !== exp_re) || (obs.filt_im !== exp_im)) begin
                mismatch_count++;
                `uvm_error("MISMATCH", $sformatf(
                    "expected (%0d, %0d) got (%0d, %0d)",
                    exp_re, exp_im, obs.filt_re, obs.filt_im))
            end else begin
                match_count++;
                `uvm_info("MATCH", $sformatf(
                    "expected == got == (%0d, %0d)", exp_re, exp_im), UVM_HIGH)
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD", $sformatf(
            "matches=%0d mismatches=%0d saturation coverage=%0.1f%%",
            match_count, mismatch_count, sat_cg.get_coverage()), UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
        if (exp_re_q.size() != 0 || observed_q.size() != 0)
            `uvm_error("SCOREBOARD", $sformatf(
                "leftover unpaired items at end of test: expected=%0d observed=%0d",
                exp_re_q.size(), observed_q.size()))
    endfunction

endclass
