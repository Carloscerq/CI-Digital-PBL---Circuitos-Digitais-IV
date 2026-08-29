`timescale 1ns / 1ps

import mlp_weights_pkg::*;

// ============================================================================
// FFT to MLP Feature Collector
// ============================================================================
// The shared FFT serialises the four vibration sensors: it emits all 64 bins
// of one sensor, raises `fft_done`, then moves on to the next. This collector
// therefore runs the single MLP time-multiplexed over the four sensors -- one
// inference per completed frame -- and reports which sensor each result came
// from on `mlp_sensor_id`.
//
// Feature map (N_IN = 132):
//   [0   .. 63 ] fft_real[bin]
//   [64  .. 127] fft_imag[bin]
//   [128 .. 131] aux sensors, selected by EXTRA_SEL and pre-shifted by
//                mlp_weights_pkg::EXTRA_SHIFT (the model expects the extras
//                already scaled down; the previous revision fed them raw).
//
// Frame admission: a frame is accepted or refused at its first bin, never
// half-way. Refusing up front is what keeps `features_reg` from being
// rewritten underneath an inference that is still reading it -- `mlp` samples
// `features` combinationally for its whole ~165-cycle run.
// ============================================================================
module fft_to_mlp_collector #(
    parameter int DATA_WIDTH = 24,
    // Which aux sensor feeds each extra slot. Index into `aux_features`,
    // whose default wiring in top_system is
    //   0,1,2 = current 0..2      3,4 = temperature 0..1
    // so '{0,1,2,3} keeps the full three-phase current set plus one
    // temperature. Retarget here if the trained model expects otherwise.
    parameter int EXTRA_SEL [4] = '{0, 1, 2, 3},
    parameter int N_AUX = 5
)(
    input  logic clk,
    input  logic reset,

    // Shared-FFT output stream
    input  logic                          fft_valid,
    input  logic                          fft_ready,
    input  logic [5:0]                    fft_bin,
    input  logic signed [DATA_WIDTH-1:0]  fft_real,
    input  logic signed [DATA_WIDTH-1:0]  fft_imag,
    input  logic                          fft_done,
    input  logic [1:0]                    fft_sensor_id,

    // Non-vibration sensors, latest value
    input  logic signed [DATA_WIDTH-1:0]  aux_features [0:N_AUX-1],

    // MLP interface
    output logic signed [ACC_WIDTH-1:0]   mlp_features [N_IN],
    output logic                          mlp_start,
    output logic [1:0]                    mlp_sensor_id,
    input  logic                          mlp_busy,

    output logic                          frame_dropped
);

    localparam int HALF  = N_BINS / 2;          // 64 real bins, then 64 imag
    localparam int IDX_W = $clog2(N_IN);        // 8 bits covers 0..131

    logic signed [ACC_WIDTH-1:0] features_reg [N_IN];
    assign mlp_features = features_reg;

    // ------------------------------------------------------------------
    // Extras: constant-folded shift, one assign per slot. Kept out of the
    // always_ff so no parameter array is ever indexed by a procedural
    // variable -- Quartus Lite turns that into a mux cone.
    // ------------------------------------------------------------------
    logic signed [ACC_WIDTH-1:0] extra_scaled [N_EXTRA];
    genvar ge;
    generate
        for (ge = 0; ge < N_EXTRA; ge++) begin : g_extra
            // EXTRA_SHIFT is negative for a right shift, hence the negation.
            assign extra_scaled[ge] =
                aux_features[EXTRA_SEL[ge]] >>> (-EXTRA_SHIFT[ge]);
        end
    endgenerate

    // ------------------------------------------------------------------
    // Frame admission
    // ------------------------------------------------------------------
    logic fft_xfer;
    logic frame_start;
    logic capturing;
    logic take;

    assign fft_xfer    = fft_valid && fft_ready;
    assign frame_start = fft_xfer && (fft_bin == 6'd0);
    assign take        = frame_start ? (!mlp_busy && !mlp_start) : capturing;

    logic [IDX_W-1:0] bin_re;
    logic [IDX_W-1:0] bin_im;
    assign bin_re = IDX_W'(fft_bin);
    assign bin_im = IDX_W'(fft_bin) + IDX_W'(HALF);

    always_ff @(posedge clk) begin
        if (reset) begin
            mlp_start     <= 1'b0;
            mlp_sensor_id <= 2'd0;
            capturing     <= 1'b0;
            frame_dropped <= 1'b0;
            for (int i = 0; i < N_IN; i++)
                features_reg[i] <= '0;
        end else begin
            mlp_start <= 1'b0;

            if (frame_start) begin
                capturing <= take;
                if (take) mlp_sensor_id <= fft_sensor_id;
                else      frame_dropped <= 1'b1;
            end

            if (fft_xfer && take) begin
                features_reg[bin_re] <= fft_real;
                features_reg[bin_im] <= fft_imag;
            end

            if (fft_done) begin
                capturing <= 1'b0;
                if (capturing) begin
                    for (int e = 0; e < N_EXTRA; e++)
                        features_reg[N_BINS + e] <= extra_scaled[e];
                    mlp_start <= 1'b1;
                end
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != ACC_WIDTH)
            $fatal(1, "[fft_to_mlp_collector] DATA_WIDTH != mlp ACC_WIDTH.");
        if (N_BINS != 2 * 64)
            $fatal(1, "[fft_to_mlp_collector] N_BINS nao casa com 64 bins re+im.");
    end
    // synthesis translate_on

endmodule
