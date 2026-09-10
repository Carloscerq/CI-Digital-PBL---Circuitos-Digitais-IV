`timescale 1ns / 1ps

// ============================================================================
// skid_buffer -- depth-2, fully registered pipeline stage
// ============================================================================
// Breaks the combinational path in BOTH handshake directions: m_valid is a
// register and s_ready is a register (!skid_full), so m_ready never reaches
// s_ready through logic. Costs one cycle of latency.
//
// Throughput is one beat per cycle while the consumer keeps up. After a stall
// it gives up a single cycle refilling the main slot from the skid slot; that
// is inherent to a depth-2 buffer, not a bug. A buffer that must absorb a long
// consumer stall needs elastic_fifo or frame_pingpong_buffer instead -- this
// one is a timing device, not a storage device.
// ============================================================================
module skid_buffer #(
    parameter int WIDTH = 8
)(
    input  logic clk,
    input  logic reset,                 // synchronous, active high

    input  logic             s_valid,
    output logic             s_ready,
    input  logic [WIDTH-1:0] s_data,

    output logic             m_valid,
    input  logic             m_ready,
    output logic [WIDTH-1:0] m_data
);

    logic [WIDTH-1:0] data_q;
    logic [WIDTH-1:0] skid_q;
    logic             skid_full;
    logic             out_free;

    assign s_ready  = !skid_full;
    assign m_data   = data_q;
    assign out_free = !m_valid || m_ready;

    always_ff @(posedge clk) begin
        if (reset) begin
            m_valid   <= 1'b0;
            skid_full <= 1'b0;
            data_q    <= '0;
            skid_q    <= '0;
        end else if (out_free) begin
            // Main slot frees this cycle: refill it from the skid slot if one
            // is held, otherwise straight from the producer.
            if (skid_full) begin
                data_q    <= skid_q;
                m_valid   <= 1'b1;
                skid_full <= 1'b0;
            end else begin
                m_valid <= s_valid && s_ready;
                if (s_valid && s_ready) data_q <= s_data;
            end
        end else begin
            // Main slot is blocked: park the incoming beat in the skid slot.
            // s_ready falls next cycle, so at most one beat can land here.
            if (s_valid && s_ready) begin
                skid_q    <= s_data;
                skid_full <= 1'b1;
            end
        end
    end

endmodule
