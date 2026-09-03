`timescale 1ns / 1ps

import mlp_weights_pkg::*;

// ============================================================================
// FFT to MLP feature collector -- ping-pong feature banks
// ============================================================================
// Assembles one 132-element MLP feature vector per ROUND of the four vibration
// sensors: 4 x 32 magnitude bins, then the four frame aggregates.
//
// >>> PINGPONG_NOTE <<<
// Two complete feature banks. The collector always writes the fill bank while
// the MLP streams the read bank, and they swap only at the instant `mlp_start`
// is issued. mlp.sv reads `features[idx]` combinationally over ~165 cycles and
// requires the vector to stay put from start to done; with a single bank that
// held only because a round takes ~4.3 s and an inference 3.3 us, so the old
// code had to DROP an entire round whenever the MLP happened to be busy at bin
// 0. Now a round that completes during an inference simply waits in the fill
// bank and starts when the engine frees up, and `frame_dropped` means what it
// says: two rounds completed without a start in between.
// ============================================================================
module fft_to_mlp_collector #(
    parameter int DATA_WIDTH = 24,
    parameter int N_VIB      = 4,    // vibration sensors in the vector
    parameter int BINS_USED  = 32,   // useful bins per sensor (half of 64)
    parameter int N_AUX      = 3,    // 1 current + 2 temperature

    // Index into aux_features for each of the first three aggregates, in the
    // order the model expects. With the top-level sensor map
    //     aux 0 = current 0     aux 1 = temperature 0     aux 2 = temperature 1
    // and the model order (Temp A, Temp B, U-phase_pow):
    parameter int EXTRA_SEL [3] = '{1, 2, 0},

    // 1 = approximate |FFT| (alpha-max-beta-min); 0 = real part only.
    // See MAGNITUDE_NOTE at the end of the file before changing this.
    parameter bit USE_MAGNITUDE = 1
)(
    input  logic clk,
    input  logic reset,                   // synchronous, active high

    // Buffered shared-FFT output stream
    input  logic                          fft_valid,
    input  logic                          fft_ready,
    input  logic [5:0]                    fft_bin,
    input  logic signed [DATA_WIDTH-1:0]  fft_real,
    input  logic signed [DATA_WIDTH-1:0]  fft_imag,
    input  logic                          fft_done,      // regenerated from `last`
    input  logic [1:0]                    fft_sensor_id,

    // Non-vibration sensors, latest value (raw, EXTRA_SHIFT not yet applied)
    input  logic signed [DATA_WIDTH-1:0]  aux_features [0:N_AUX-1],

    // Fourth model aggregate. Does NOT come from aux_features -- see MDC_K0_NOTE.
    input  logic signed [DATA_WIDTH-1:0]  mdc_k0,

    // MLP interface
    output logic signed [ACC_WIDTH-1:0]   mlp_features [N_IN],
    output logic                          mlp_start,
    input  logic                          mlp_busy,

    output logic                          frame_dropped
);

    localparam int IDX_W = $clog2(N_IN);

    // ------------------------------------------------------------------
    // Bin magnitude
    // ------------------------------------------------------------------
    // |z| = sqrt(re^2 + im^2) is expensive. The alpha-max-beta-min estimate
    //   |z| ~= max(|re|,|im|) + 0.375 * min(|re|,|im|)
    // is off by at most ~6.8% and costs only adders and shifts, no multiplier.
    // 0.375 = 1/2 - 1/8, hence (mn>>1) - (mn>>3).
    function automatic logic [DATA_WIDTH-1:0] abs_sat (input logic signed [DATA_WIDTH-1:0] v);
        if (!v[DATA_WIDTH-1])                         return v[DATA_WIDTH-1:0];
        else if (v == {1'b1, {(DATA_WIDTH-1){1'b0}}}) return {1'b0, {(DATA_WIDTH-1){1'b1}}};
        else                                          return (-v);
    endfunction

    logic [DATA_WIDTH-1:0]       abs_re, abs_im, mx, mn;
    logic [DATA_WIDTH+1:0]       mag_full;
    logic signed [ACC_WIDTH-1:0] bin_feature;

    always_comb begin
        abs_re = abs_sat(fft_real);
        abs_im = abs_sat(fft_imag);
        mx     = (abs_re >= abs_im) ? abs_re : abs_im;
        mn     = (abs_re >= abs_im) ? abs_im : abs_re;

        mag_full = {2'b0, mx} + {2'b0, (mn >> 1)} - {2'b0, (mn >> 3)};

        if (USE_MAGNITUDE) begin
            // saturate at the largest representable positive value
            if (mag_full > {2'b0, 1'b0, {(DATA_WIDTH-1){1'b1}}})
                bin_feature = ACC_WIDTH'({1'b0, {(DATA_WIDTH-1){1'b1}}});
            else
                bin_feature = ACC_WIDTH'(mag_full[DATA_WIDTH-1:0]);
        end else begin
            bin_feature = ACC_WIDTH'(fft_real);
        end
    end

    // ------------------------------------------------------------------
    // Frame aggregates
    // ------------------------------------------------------------------
    // The datapath gain the training notebook divides W0 by:
    //   HW_GAIN_BIN = 2^Q_FRAC / N_FFT = 2^15 / 2^6 = 2^9
    localparam int HW_GAIN_LOG2 = Q_FRAC - $clog2(2*BINS_USED);   // 15 - 6 = 9

    logic signed [ACC_WIDTH-1:0] extra_scaled [N_EXTRA];

    // The three UART aggregates arrive already multiplied by 2^9 by the host,
    // so only EXTRA_SHIFT remains to be applied here.
    assign extra_scaled[0] = aux_features[EXTRA_SEL[0]] >>> (-EXTRA_SHIFT[0]); // Temp A
    assign extra_scaled[1] = aux_features[EXTRA_SEL[1]] >>> (-EXTRA_SHIFT[1]); // Temp B
    assign extra_scaled[2] = aux_features[EXTRA_SEL[2]] >>> (-EXTRA_SHIFT[2]); // U-phase_pow

    // >>> MDC_K0_NOTE <<<
    // mdc_k0 is born INSIDE the FPGA as a plain bin index, so unlike the three
    // UART aggregates it never picks up the 2^9 datapath gain. Net shift is
    // therefore HW_GAIN_LOG2 + EXTRA_SHIFT[3] = 9 - 6 = +3.
    // k0 = 8 (50 Hz) -> 64, exactly the top of the 0..64 range the model expects.
    localparam int MDC_NET_SHIFT = HW_GAIN_LOG2 + EXTRA_SHIFT[3];  // 9 - 6 = 3
    assign extra_scaled[3] = mdc_k0 <<< MDC_NET_SHIFT;

    // ------------------------------------------------------------------
    // Ping-pong feature banks
    // ------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] bank0 [N_IN];
    logic signed [ACC_WIDTH-1:0] bank1 [N_IN];

    logic fill_bank;      // bank the collector writes
    logic read_bank;      // bank the MLP reads; invariant: read_bank != fill_bank
    logic start_pending;  // a completed round is waiting for the engine

    genvar i;
    generate
        for (i = 0; i < N_IN; i++) begin : g_feat_mux
            assign mlp_features[i] = read_bank ? bank1[i] : bank0[i];
        end
    endgenerate

    // ------------------------------------------------------------------
    // Round assembly
    // ------------------------------------------------------------------
    logic             fft_xfer;
    logic             bin_in_range;
    logic [IDX_W-1:0] bin_addr;
    logic [N_VIB-1:0] round_mask;      // sensors already folded into this round
    logic [N_VIB-1:0] next_mask;
    logic             round_complete;
    logic             issue_start;

    assign fft_xfer     = fft_valid && fft_ready;
    assign bin_in_range = (fft_bin < 6'(BINS_USED));

    // Position of the bin inside the vector: sensor * BINS_USED + bin
    assign bin_addr = IDX_W'(fft_sensor_id) * IDX_W'(BINS_USED) + IDX_W'(fft_bin);

    assign next_mask      = round_mask | (N_VIB'(1) << fft_sensor_id);
    assign round_complete = fft_done && (&next_mask);

    // Swap and launch as soon as the engine is free. mlp_start is registered,
    // so read_bank switches on the same edge the MLP samples start -- it reads
    // features[idx] only from the following cycle onward.
    assign issue_start = start_pending && !mlp_busy && !mlp_start;

    always_ff @(posedge clk) begin
        if (reset) begin
            mlp_start     <= 1'b0;
            round_mask    <= '0;
            frame_dropped <= 1'b0;
            fill_bank     <= 1'b0;
            read_bank     <= 1'b1;
            start_pending <= 1'b0;
            for (int k = 0; k < N_IN; k++) begin
                bank0[k] <= '0;
                bank1[k] <= '0;
            end
        end else begin
            mlp_start <= 1'b0;

            // Only bins 0..BINS_USED-1 become features; the rest are the
            // conjugate mirror and carry no new information.
            if (fft_xfer && bin_in_range) begin
                if (!fill_bank) bank0[bin_addr] <= bin_feature;
                else            bank1[bin_addr] <= bin_feature;
            end

            if (fft_done) begin
                if (round_complete) begin
                    // Freeze the aggregates into the same bank as the bins.
                    for (int e = 0; e < N_EXTRA; e++) begin
                        if (!fill_bank) bank0[N_BINS + e] <= extra_scaled[e];
                        else            bank1[N_BINS + e] <= extra_scaled[e];
                    end
                    round_mask    <= '0;
                    start_pending <= 1'b1;

                    // The previous round never got launched: it is about to be
                    // overwritten in the fill bank.
                    if (start_pending) frame_dropped <= 1'b1;
                end else begin
                    round_mask <= next_mask;
                end
            end

            if (issue_start) begin
                read_bank     <= fill_bank;
                fill_bank     <= ~fill_bank;
                mlp_start     <= 1'b1;
                start_pending <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // MAGNITUDE_NOTE
    // ------------------------------------------------------------------
    // The training notebook feeds |rFFT| to the model, so USE_MAGNITUDE = 1 is
    // the setting that matches the exported weights. USE_MAGNITUDE = 0 exists
    // only to compare against a real-part-only build; it does not match any
    // trained model.

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != ACC_WIDTH)
            $fatal(1, "[fft_to_mlp_collector] DATA_WIDTH != mlp ACC_WIDTH.");
        if (N_BINS != N_VIB * BINS_USED)
            $fatal(1, "[fft_to_mlp_collector] N_BINS (%0d) != N_VIB*BINS_USED (%0d).",
                   N_BINS, N_VIB * BINS_USED);
        if (N_EXTRA != 4)
            $fatal(1, "[fft_to_mlp_collector] N_EXTRA=%0d; the aggregate map assumes 4.",
                   N_EXTRA);
    end
    // synthesis translate_on

endmodule
