`timescale 1ns / 1ps

// ============================================================================
// Spectrogram Join: four 1-channel streams -> the CNN's 4-channel slave port
// ============================================================================
// cnn_top consumes IN_CHANNELS = 4 co-located pixels per beat, one per
// vibration sensor. Each sensor owns its own spectrogram_generator, so this
// joiner walks all four in lockstep: a beat is presented only when every
// channel has a pixel, and the ready is broadcast so all four advance
// together.
//
// The four generators stay aligned because the shared FFT accepts the four
// sensor samples atomically and then round-robins their frames, so each
// generator sees exactly one row per FFT frame. `desync_error` latches if that
// ever stops being true -- it is the only way a lockstep join can deadlock.
// ============================================================================
module spectrogram_4ch_join #(
    parameter int DATA_WIDTH = 24,
    parameter int CHANNELS   = 4
)(
    input  logic clk,
    input  logic reset,

    // Spectrogram masters (one per sensor)
    input  logic [CHANNELS-1:0]          m_valid,
    output logic [CHANNELS-1:0]          m_ready,
    input  logic signed [DATA_WIDTH-1:0] m_data [0:CHANNELS-1],
    input  logic [CHANNELS-1:0]          m_last,

    // CNN slave
    output logic                         s_valid,
    input  logic                         s_ready,
    output logic signed [DATA_WIDTH-1:0] s_data [0:CHANNELS-1],
    output logic                         s_last,

    output logic                         desync_error
);

    logic all_valid;
    assign all_valid = &m_valid;

    assign s_valid = all_valid;
    assign s_last  = m_last[0];
    assign m_ready = {CHANNELS{all_valid && s_ready}};

    genvar c;
    generate
        for (c = 0; c < CHANNELS; c++) begin : g_data
            assign s_data[c] = m_data[c];
        end
    endgenerate

    // All four channels must reach the end of a spectrogram on the same beat.
    always_ff @(posedge clk) begin
        if (reset)
            desync_error <= 1'b0;
        else if (all_valid && s_ready &&
                 (m_last != {CHANNELS{m_last[0]}}))
            desync_error <= 1'b1;
    end

endmodule
