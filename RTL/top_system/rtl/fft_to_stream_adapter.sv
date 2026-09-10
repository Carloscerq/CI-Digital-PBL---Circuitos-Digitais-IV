`timescale 1ns / 1ps

// ============================================================================
// FFT to Stream Adapter (one per CNN input channel)
// ============================================================================
// The shared FFT tags every bin with the sensor it belongs to, so each of the
// four spectrogram front-ends filters the single output stream down to its own
// sensor and forwards the first BINS_PER_FRAME bins as one spectrogram row.
//
// `s_ready` is fed back to the FFT's `fft_ready` in top_system, so
// backpressure stalls the FFT output stage instead of silently dropping bins
// the way the previous always-ready wiring did.
//
// `s_last` marks the end of a whole SPECTROGRAM (BINS_PER_FRAME *
// FRAMES_PER_SPECTROGRAM words), not the end of a row. spectrogram_generator
// treats `s_last` as "close this buffer now", so raising it once per row
// -- as this adapter previously did -- would hand the CNN a 32-word image
// instead of the 32x32 one it is built for.
//
// >>> MAGNITUDE_NOTE <<<
// This forwards |X[k]|, not Re(X[k]). It used to forward the real part, which
// is the wrong feature for a spectrogram: the 64-sample frame boundary is not
// phase-locked to the shaft, so Re(X[k]) changes sign essentially at random
// from one row to the next. Measured on the capture set, the frame-to-frame
// coherence of the real part -- |mean(Re)| / mean(|Re|) -- runs 0.006 to 0.040,
// i.e. it averages to nothing. The CNN was being handed a sign-randomised
// spectrum. Magnitude is phase-invariant and stable.
//
// The approximation is alpha-max-beta-min, |z| ~= max + (min>>1) - (min>>3),
// the SAME one fft_peak_mdc.sv:71-90 and fft_to_mlp_collector use. Keeping all
// three identical means the CNN and the MLP see the same notion of "magnitude"
// and costs no multiplier. If you change it in one place, change it in all
// three.
//
// The output is non-negative and saturates at 2^(DATA_WIDTH-1)-1, so it still
// fits the signed datapath every downstream module (spectrogram_generator,
// spectrogram_4ch_join, frame_pingpong_buffer, cnn_top) already uses.
// ============================================================================
module fft_to_stream_adapter #(
    parameter int DATA_WIDTH             = 24,
    parameter int BINS_PER_FRAME         = 32,
    parameter int FRAMES_PER_SPECTROGRAM = 32,
    parameter int SENSOR_ID              = 0
)(
    input  logic clk,
    input  logic reset,

    // FFT side
    input  logic                         fft_valid,
    input  logic [5:0]                   fft_bin,
    input  logic [1:0]                   fft_sensor_id,
    input  logic signed [DATA_WIDTH-1:0] fft_real,
    input  logic signed [DATA_WIDTH-1:0] fft_imag,

    // Stream master side (to spectrogram_generator)
    output logic                         s_valid,
    input  logic                         s_ready,
    output logic signed [DATA_WIDTH-1:0] s_data,
    output logic                         s_last
);

    localparam int ROW_W    = (FRAMES_PER_SPECTROGRAM > 1)
                              ? $clog2(FRAMES_PER_SPECTROGRAM) : 1;
    localparam int LAST_BIN = BINS_PER_FRAME - 1;
    localparam int LAST_ROW = FRAMES_PER_SPECTROGRAM - 1;

    logic [ROW_W-1:0] row;
    logic row_end;

    // ------------------------------------------------------------------
    // Bin magnitude. See MAGNITUDE_NOTE.
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

    assign s_valid = fft_valid &&
                          (fft_sensor_id == 2'(SENSOR_ID)) &&
                          (fft_bin < 6'(BINS_PER_FRAME));
    // Non-negative and capped at 2^23-1, so the signed cast never wraps.
    assign s_data  = $signed({1'b0, bin_mag[DATA_WIDTH-2:0]});

    assign row_end      = s_valid && (fft_bin == 6'(LAST_BIN));
    assign s_last  = row_end && (row == ROW_W'(LAST_ROW));

    always_ff @(posedge clk) begin
        if (reset)
            row <= '0;
        else if (row_end && s_ready)
            row <= (row == ROW_W'(LAST_ROW)) ? '0 : (row + 1'b1);
    end

endmodule
