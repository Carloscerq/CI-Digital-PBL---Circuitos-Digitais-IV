`timescale 1ns / 1ps

// ============================================================================
// fft_peak_mdc -- spectral peak detector + GCD module (Euclid)
// ============================================================================
// Sum the four vibration channels bin by bin, take the three strongest LOCAL
// MAXIMA above a relative threshold inside bins 1..K_MAX, and return their GCD
// as k0, the fundamental rotation bin. f0 = k0 * fs/(DECIM_RATE*FFT_N), which
// at the live DECIM_RATE = 32 is k0 * 12.5 Hz.
//
// >>> K_MAX_NOTE <<<
// K_MAX is a FREQUENCY limit wearing a bin index, so it tracks the decimation
// rate. The band that works is ~162.5 Hz: one bin of headroom above the shaft
// 3x (150 Hz), and below the 168.8/182.8/193.8/200.8 Hz machine lines, which
// are NOT rotation harmonics and wreck the GCD when they reach the top three
// (gcd(4,8,14) = 2). That is bin 26 at 6.25 Hz/bin and bin 13 at 12.5 Hz/bin,
// so top_system derives K_MAX from DECIM_RATE instead of passing a constant
// (MDC_BAND_NOTE in system_types_pkg.sv) and the two cannot drift apart again.
//
// Measured over the 56 250 frames of all 45 captures at the live 12.5 Hz/bin,
// with the hold register reset per capture, by replaying this module on the
// real front end (Scripts/train_mlp.py --no-export):
//
//   K_MAX  band     locks   held k0 = 4   modal k0 when it locks
//      12  150 Hz   11.8%   52.6%         4  = 50.0 Hz, correct
//      13  162 Hz   11.8%   52.6%         4  = 50.0 Hz, correct   <-- live
//      14  175 Hz   33.6%   13.5%         2  = 25.0 Hz, wrong (168.8 Hz line)
//      26  325 Hz   26.7%    3.0%         3  = 37.5 Hz, wrong
//
// A wider band locks MORE OFTEN onto the WRONG thing. 26 was inherited from the
// 6.25 Hz/bin build, where it meant the same 162.5 Hz; carried over unchanged
// to 12.5 Hz/bin it reports 37.5 Hz for a shaft that turns at 50, which is why
// K_MAX is now derived rather than pasted. Widening it to match SPEC_BINS looks
// like an obvious cleanup and silently destroys the module.
//
// >>> HONEST_TRADEOFF_NOTE <<<
// Correcting the band makes the ESTIMATOR right and the CLASSIFIER slightly
// worse, and it is worth knowing why before someone "fixes" it back. In a
// 13-bin band three local maxima are rare, so the module locks on only ~12% of
// frames and 42% of frames sit at k0 = 0, never having locked yet within their
// capture. That turns k0 into a "has this capture locked yet" flag, which
// correlates with capture identity and does not survive a split by capture:
// macro recall 0.755 against 0.805 for the old wrong-but-noisy k0, and 0.808
// with no k0 information at all. Lowering THR_SH only reaches ~20% lock; the
// binding constraint is N_PEAKS = 3, which is fixed because the tracker below
// is unrolled. So k0 is carried because the fundamental frequency is a required
// output, not because it earns its place in the feature vector.
// ============================================================================

module fft_peak_mdc #(
    parameter int DATA_WIDTH = 24,
    parameter int N_VIB      = 4,    // channels summed; MUST BE A POWER OF 2
    parameter int K_MAX      = 13,   // last bin of the search -- see K_MAX_NOTE
    parameter int K_MIN      = 2,    // k0 < K_MIN => invalid (MDC_K_MIN)
    parameter int N_PEAKS    = 3,    // fixed at 3: the tracker is unrolled
    // Relative threshold. The notebook uses 0.15; here it becomes
    // (mx>>3) + (mx>>5) = 5/32 = 0.15625, which costs only shifts.
    parameter int THR_SH_A   = 3,
    parameter int THR_SH_B   = 5
)(
    input  logic clk,
    input  logic reset,

    // Buffered shared-FFT output stream
    input  logic                         fft_valid,
    input  logic                         fft_ready,
    input  logic [5:0]                   fft_bin,
    input  logic signed [DATA_WIDTH-1:0] fft_real,
    input  logic signed [DATA_WIDTH-1:0] fft_imag,
    input  logic [1:0]                   fft_sensor_id,
    input  logic                         fft_done,

    output logic signed [DATA_WIDTH-1:0] mdc_k0,      // last valid k0 (held)
    output logic                         mdc_valid,   // level: this round locked
    output logic                         mdc_update,  // pulse: k0/valid updated
    output logic                         mdc_overrun  // sticky: new round arrived too early
);

    // A local maximum at k needs mag[k-1] and mag[k+1], so the accumulator
    // holds bins 0 .. K_MAX+1. Bin 0 is never a peak candidate (the search
    // starts at 1) but it is the left neighbour of k = 1.
    localparam int ACC_N = K_MAX + 2;
    localparam int ACC_W = DATA_WIDTH + $clog2(N_VIB);   // 24 + 2 = 26
    localparam int K_W   = $clog2(ACC_N);                // 4 at K_MAX = 13

    localparam logic [2:0] S_IDLE = 3'd0,   // waiting for a round to end
                           S_MAX  = 3'd1,   // pass 1: largest bin in the band
                           S_SCAN = 3'd2,   // pass 2: local maxima + top 3
                           S_GCD  = 3'd3,   // Euclid over k1, k2, k3
                           S_UPD  = 3'd4;   // validate and hold the result

    // ------------------------------------------------------------------
    // Bin magnitude -- the SAME approximation fft_to_mlp_collector uses
    // (alpha-max-beta-min, |z| ~= max + 0.375*min = max + (min>>1) - (min>>3)).
    // Duplicated on purpose: the peak ranking has to see exactly the magnitude
    // that becomes a feature. If you change it there, change it here too.
    // The MDC threshold is RELATIVE, so the approximation's ~7% error cancels
    // between the peak and the band maximum.
    // ------------------------------------------------------------------
    function automatic logic [DATA_WIDTH-1:0] abs_sat (input logic signed [DATA_WIDTH-1:0] v);
        if (!v[DATA_WIDTH-1])                         return v[DATA_WIDTH-1:0];
        else if (v == {1'b1, {(DATA_WIDTH-1){1'b0}}}) return {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else                                          return (-v);
    endfunction

    logic [DATA_WIDTH-1:0] abs_re, abs_im, mx_c, mn_c;
    logic [DATA_WIDTH+1:0] mag_full;
    logic [DATA_WIDTH-1:0] bin_mag;

    always_comb begin
        abs_re   = abs_sat(fft_real);
        abs_im   = abs_sat(fft_imag);
        mx_c     = (abs_re >= abs_im) ? abs_re : abs_im;
        mn_c     = (abs_re >= abs_im) ? abs_im : abs_re;
        mag_full = {2'b0, mx_c} + {2'b0, (mn_c >> 1)} - {2'b0, (mn_c >> 3)};
        bin_mag  = (mag_full > {2'b0, 1'b0, {(DATA_WIDTH-1){1'b1}}})
                 ? {1'b0, {(DATA_WIDTH-1){1'b1}}}
                 : mag_full[DATA_WIDTH-1:0];
    end

    // ------------------------------------------------------------------
    // Per-bin accumulator: the sum of the N_VIB channel magnitudes, which is
    // what the notebook feeds the detector (mag_sum, not a per-sensor spectrum).
    // The shared FFT delivers one sensor at a time in ascending bin order, so
    // sensor 0 WRITES and the others ACCUMULATE. No clear pass is needed.
    // ------------------------------------------------------------------
    logic [ACC_W-1:0] mag_acc [ACC_N];

    logic fft_xfer, acc_in_range, acc_first, round_end;
    assign fft_xfer     = fft_valid && fft_ready;
    assign acc_in_range = fft_xfer && (fft_bin < 6'(ACC_N));
    assign acc_first    = (fft_sensor_id == 2'd0);
    assign round_end    = fft_done && (fft_sensor_id == 2'(N_VIB-1));

    always_ff @(posedge clk) begin
        if (acc_in_range) begin
            if (acc_first)
                mag_acc[fft_bin[K_W-1:0]] <= ACC_W'(bin_mag);
            else
                mag_acc[fft_bin[K_W-1:0]] <= mag_acc[fft_bin[K_W-1:0]] + ACC_W'(bin_mag);
        end
    end

    // ------------------------------------------------------------------
    // Scan: band maximum first, then local maxima above the threshold
    // ------------------------------------------------------------------
    logic [2:0]       state;
    logic [K_W-1:0]   k;
    logic [ACC_W-1:0] band_max, thr;
    logic [ACC_W-1:0] pmag1, pmag2, pmag3;
    logic [5:0]       pk1, pk2, pk3;
    logic [1:0]       n_peaks;

    // Three simultaneous reads of the register bank: k-1, k, k+1.
    // In S_SCAN, k runs 1..K_MAX, so the indices stay inside 0..K_MAX+1.
    logic [ACC_W-1:0] a_prev, a_cur, a_next;
    assign a_prev = mag_acc[k - K_W'(1)];
    assign a_cur  = mag_acc[k];
    assign a_next = mag_acc[k + K_W'(1)];

    logic is_local_max, is_peak;
    assign is_local_max = (a_cur > a_prev) && (a_cur >= a_next);
    assign is_peak      = is_local_max && (a_cur >= thr);

    // Band maximum including the current bin, used on the last cycle of S_MAX
    // to close the threshold without spending an extra state.
    logic [ACC_W-1:0] band_max_next;
    assign band_max_next = (a_cur > band_max) ? a_cur : band_max;

    logic [5:0] gcd_in [3];
    logic [5:0] gcd_out;
    logic [5:0] k0_result;
    logic       gcd_start, gcd_ready, gcd_busy;

    gcd #(.AMOUNT_OF_NUMBERS(3), .SIZE(6)) u_gcd (
        .clk   (clk),
        .reset (reset),
        .start (gcd_start),
        .in    (gcd_in),
        .out   (gcd_out),
        .ready (gcd_ready)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state       <= S_IDLE;
            k           <= K_W'(1);
            band_max    <= '0;
            thr         <= '0;
            pmag1       <= '0;  pmag2 <= '0;  pmag3 <= '0;
            pk1         <= 6'd0; pk2  <= 6'd0; pk3  <= 6'd0;
            n_peaks     <= 2'd0;
            gcd_in[0]   <= 6'd0; gcd_in[1] <= 6'd0; gcd_in[2] <= 6'd0;
            k0_result   <= 6'd0;
            gcd_start   <= 1'b0;
            gcd_busy    <= 1'b0;
            mdc_k0      <= '0;          // notebook: k0 initialises to 0
            mdc_valid   <= 1'b0;
            mdc_update  <= 1'b0;
            mdc_overrun <= 1'b0;
        end else begin
            gcd_start  <= 1'b0;
            mdc_update <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                S_IDLE: begin
                    if (round_end) begin
                        band_max <= '0;
                        pmag1    <= '0;  pmag2 <= '0;  pmag3 <= '0;
                        pk1      <= 6'd0; pk2  <= 6'd0; pk3  <= 6'd0;
                        n_peaks  <= 2'd0;
                        k        <= K_W'(1);
                        state    <= S_MAX;
                    end
                end

                // ----------------------------------------------------------
                // The notebook's mag[1:K_MAX+1].max(): the threshold reference.
                S_MAX: begin
                    if (a_cur > band_max) band_max <= a_cur;

                    if (k == K_W'(K_MAX)) begin
                        // 0.15625 = 1/8 + 1/32, shifts only
                        thr   <= (band_max_next >> THR_SH_A)
                               + (band_max_next >> THR_SH_B);
                        k     <= K_W'(1);
                        state <= S_SCAN;
                    end else begin
                        k <= k + K_W'(1);
                    end
                end

                // ----------------------------------------------------------
                // Local maxima above the threshold, keeping the largest three.
                // Strict comparison (>) means a tie is won by the LOWER bin
                // index, which biases towards the fundamental rather than a
                // harmonic.
                S_SCAN: begin
                    if (is_peak) begin
                        if (n_peaks != 2'd3) n_peaks <= n_peaks + 2'd1;

                        if (a_cur > pmag1) begin
                            pmag1 <= a_cur;  pk1 <= 6'(k);
                            pmag2 <= pmag1;  pk2 <= pk1;
                            pmag3 <= pmag2;  pk3 <= pk2;
                        end else if (a_cur > pmag2) begin
                            pmag2 <= a_cur;  pk2 <= 6'(k);
                            pmag3 <= pmag2;  pk3 <= pk2;
                        end else if (a_cur > pmag3) begin
                            pmag3 <= a_cur;  pk3 <= 6'(k);
                        end
                    end

                    if (k == K_W'(K_MAX)) begin
                        state <= S_GCD;
                    end else begin
                        k <= k + K_W'(1);
                    end
                end

                // ----------------------------------------------------------
                // Fewer than MDC_N_PEAKS peaks above the threshold marks the
                // result invalid -- Euclid is not run at all in that case.
                S_GCD: begin
                    if (!gcd_busy && !gcd_start) begin
                        if (n_peaks == 2'd3) begin
                            gcd_in[0] <= pk1;
                            gcd_in[1] <= pk2;
                            gcd_in[2] <= pk3;
                            gcd_start <= 1'b1;
                            gcd_busy  <= 1'b1;
                        end else begin
                            // invalid: hold the last k0, just drop valid
                            mdc_valid  <= 1'b0;
                            mdc_update <= 1'b1;
                            state      <= S_IDLE;
                        end
                    end else if (gcd_ready) begin
                        // the gcd `out` is only meaningful while `ready` is high
                        gcd_busy  <= 1'b0;
                        k0_result <= gcd_out;
                        state     <= S_UPD;
                    end
                end

                // ----------------------------------------------------------
                // k0 < K_MIN means GCD(...) = 1, i.e. no harmonic series:
                // invalid. Valid => an enabled register holds the new k0.
                S_UPD: begin
                    if (k0_result >= 6'(K_MIN)) begin
                        mdc_k0    <= DATA_WIDTH'(k0_result);
                        mdc_valid <= 1'b1;
                    end else begin
                        mdc_valid <= 1'b0;
                    end
                    mdc_update <= 1'b1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase

            // A new round must not arrive while the previous scan is running.
            // With HOP_SIZE = 64 rounds are seconds apart and the scan takes
            // ~200 cycles, so this is a guard, not an expected condition.
            if (round_end && (state != S_IDLE))
                mdc_overrun <= 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (N_PEAKS != 3)
            $fatal(1, "[fft_peak_mdc] N_PEAKS=%0d; the top-3 tracker is unrolled.", N_PEAKS);
        if (N_VIB != (1 << $clog2(N_VIB)))
            $fatal(1, "[fft_peak_mdc] N_VIB=%0d is not a power of 2.", N_VIB);
        if (K_MAX + 1 > 63)
            $fatal(1, "[fft_peak_mdc] K_MAX=%0d does not fit the 6 bits of fft_bin.", K_MAX);
        if (K_MIN < 1)
            $fatal(1, "[fft_peak_mdc] K_MIN=%0d is invalid.", K_MIN);
    end
    // synthesis translate_on

endmodule
