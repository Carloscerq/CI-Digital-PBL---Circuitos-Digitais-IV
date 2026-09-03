`timescale 1ns / 1ps

// ============================================================================
// sensor_ingestion_subsystem
// ============================================================================
// Everything between the UART pin and the DSP front end: baud generation,
// byte reception, frame deserialisation, and an elastic FIFO on the vibration
// path.
//
// >>> ELASTICITY_NOTE <<<
// A UART cannot be back-pressured, so the old design held one vibration quad
// in a single register and latched `vib_overrun` if the DSP had not taken it
// before the next frame landed. The FIFO replaces that register with real
// elasticity: FIFO_DEPTH frames of slack, which at 480 frames/s is
// 64/480 = 133 ms. Note this is insurance, not a rate fix -- UART delivers
// 480 samples/s per channel and the decimate-by-32 front end consumes exactly
// that, so the rates already match and the pre-existing slack in the 64-deep
// sample buffers is around 4.3 s. The FIFO makes the boundary explicit rather
// than leaving it as an arithmetic coincidence.
//
// >>> AUX_BYPASS_NOTE <<<
// Only the four vibration words are queued. The three aggregates (current,
// two temperatures) are frame statistics that the MLP collector latches at
// round boundaries, so they are exposed as a live "latest value" bus instead.
// Queueing them alongside the vibration samples would hand the collector
// aggregates belonging to a different round.
// ============================================================================
module sensor_ingestion_subsystem #(
    parameter int CLK_FREQ_HZ        = 50_000_000,
    parameter int BAUD_RATE          = 115_200,
    parameter int FIFO_DEPTH         = 64,
    parameter int IDLE_TIMEOUT_BYTES = 4
)(
    input  logic clk,
    input  logic reset,                          // synchronous, active high

    input  logic uart_rx,                        // raw pin

    // Vibration quad, elastic
    output system_types_pkg::vib_bus_t m_vib_data,
    output logic                       m_vib_valid,
    input  logic                       m_vib_ready,

    // Frame aggregates, latest value (bypasses the FIFO on purpose)
    output system_types_pkg::aux_bus_t aux_data,

    // Health
    output logic frame_error,                    // pulse: framing / checksum
    output logic vib_overrun                     // sticky: FIFO dropped a quad
);

    import system_types_pkg::*;

    // ------------------------------------------------------------------
    // Pin synchroniser
    // ------------------------------------------------------------------
    logic [2:0] uart_rx_sync;
    always_ff @(posedge clk) begin
        if (reset) uart_rx_sync <= 3'b111;
        else       uart_rx_sync <= {uart_rx_sync[1:0], uart_rx};
    end

    // ------------------------------------------------------------------
    // UART receive
    // ------------------------------------------------------------------
    logic [7:0] uart_rx_data;
    logic       uart_rx_ready;
    logic       uart_rx_ready_clr;
    logic       uart_rx_clk_en;
    logic       uart_tx_clk_en_unused;

    baudrate #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .OVERSAMPLE (16)
    ) u_uart_baud (
        .clk      (clk),
        .rst      (reset),
        .rx_clk_en(uart_rx_clk_en),
        .tx_clk_en(uart_tx_clk_en_unused)
    );

    receiver #(
        .OVERSAMPLE(16)
    ) u_uart_rx (
        .clk      (clk),
        .rst      (reset),
        .clk_en   (uart_rx_clk_en),
        .rx       (uart_rx_sync[2]),
        .rx_en    (1'b0),           // rx_en is ACTIVE LOW: 0 = enabled
        .ready_clr(uart_rx_ready_clr),
        .ready    (uart_rx_ready),
        .data     (uart_rx_data)
    );

    logic signed [DATA_WIDTH-1:0] sensor_data [0:N_SENSORS-1];
    logic sensor_frame_valid;

    uart_sensor_frame_rx #(
        .DATA_WIDTH        (DATA_WIDTH),
        .N_SENSORS         (N_SENSORS),
        .BYTES_PER_WORD    (BYTES_PER_WORD),
        .CLK_FREQ_HZ       (CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .IDLE_TIMEOUT_BYTES(IDLE_TIMEOUT_BYTES)
    ) u_frame_rx (
        .clk         (clk),
        .reset       (reset),
        .rx_data     (uart_rx_data),
        .rx_ready    (uart_rx_ready),
        .rx_ready_clr(uart_rx_ready_clr),
        .sensor_data (sensor_data),
        .frame_valid (sensor_frame_valid),
        .frame_error (frame_error)
    );

    // ------------------------------------------------------------------
    // Word map
    // ------------------------------------------------------------------
    // Words 0..N_VIB-1        : vibration    -> FFT
    // Words AUX_BASE..N_SENSORS-1 : current 0, temperature 0, temperature 1
    logic [N_VIB*DATA_WIDTH-1:0] vib_packed;

    genvar v, a;
    generate
        for (v = 0; v < N_VIB; v++) begin : g_vib_pack
            assign vib_packed[v*DATA_WIDTH +: DATA_WIDTH] = sensor_data[v];
        end
        // sensor_data holds its value between good frames, so the aggregates
        // need no register of their own here.
        for (a = 0; a < N_AUX; a++) begin : g_aux_pack
            assign aux_data[a*DATA_WIDTH +: DATA_WIDTH] = sensor_data[AUX_BASE + a];
        end
    endgenerate

    // ------------------------------------------------------------------
    // Elastic boundary to the DSP front end
    // ------------------------------------------------------------------
    elastic_fifo #(
        .WIDTH(N_VIB*DATA_WIDTH),
        .DEPTH(FIFO_DEPTH)
    ) u_vib_fifo (
        .clk     (clk),
        .reset   (reset),
        .s_valid (sensor_frame_valid),
        .s_ready (),                  // UART cannot stall; overrun == a lost quad
        .s_data  (vib_packed),
        .m_valid (m_vib_valid),
        .m_ready (m_vib_ready),
        .m_data  (m_vib_data),
        .overrun (vib_overrun),
        .level   ()
    );

endmodule
