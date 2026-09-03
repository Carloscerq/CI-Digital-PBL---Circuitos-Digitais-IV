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

    assign s_valid = fft_valid &&
                          (fft_sensor_id == 2'(SENSOR_ID)) &&
                          (fft_bin < 6'(BINS_PER_FRAME));
    assign s_data  = fft_real;

    assign row_end      = s_valid && (fft_bin == 6'(LAST_BIN));
    assign s_last  = row_end && (row == ROW_W'(LAST_ROW));

    always_ff @(posedge clk) begin
        if (reset)
            row <= '0;
        else if (row_end && s_ready)
            row <= (row == ROW_W'(LAST_ROW)) ? '0 : (row + 1'b1);
    end

endmodule
