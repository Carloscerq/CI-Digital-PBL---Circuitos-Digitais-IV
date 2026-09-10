`timescale 1ns / 1ps

// ============================================================================
// elastic_fifo -- synchronous FIFO, first-word-fall-through
// ============================================================================
// Absorbs producer bursts so a stalled consumer cannot force the producer to
// drop data. `full` and `empty` are held in registers rather than derived from
// a pointer comparison, so s_ready and m_valid are single flip-flops and
// m_ready never reaches s_ready through logic.
//
// First-word-fall-through: m_data is the head of the queue combinationally, so
// this drops into a valid/ready link with no output wrapper. m_valid is still
// a register.
//
// >>> OVERRUN_NOTE <<<
// `overrun` is sticky and latches when a beat is offered while the FIFO is
// full. Read it according to the producer:
//   - a producer that CANNOT be back-pressured (the UART frame receiver pulses
//     frame_valid for one cycle and never retries) -- this is a LOST word;
//   - a producer that honours s_ready and holds its data -- this is only a
//     back-pressure event, and nothing was lost.
// The FIFO cannot tell the two apart, so the flag is named for the event, not
// for the consequence. `level` exists for SignalTap only.
// ============================================================================
module elastic_fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 64            // must be a power of two, >= 2
)(
    input  logic clk,
    input  logic reset,                 // synchronous, active high

    input  logic             s_valid,
    output logic             s_ready,
    input  logic [WIDTH-1:0] s_data,

    output logic             m_valid,
    input  logic             m_ready,
    output logic [WIDTH-1:0] m_data,

    output logic                   overrun,
    output logic [$clog2(DEPTH):0] level
);

    localparam int PTR_W = $clog2(DEPTH);
    localparam int LVL_W = PTR_W + 1;

    (* ramstyle = "no_rw_check" *)
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    logic [PTR_W-1:0] wr_ptr, rd_ptr;
    logic             full_q, empty_q;
    logic             push, pop;

    assign s_ready = !full_q;
    assign m_valid = !empty_q;
    assign m_data  = mem[rd_ptr];
    assign push    = s_valid && s_ready;
    assign pop     = m_valid && m_ready;

    always_ff @(posedge clk) begin
        if (push) mem[wr_ptr] <= s_data;
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_ptr   <= '0;
            rd_ptr   <= '0;
            full_q   <= 1'b0;
            empty_q  <= 1'b1;
            level    <= '0;
            overrun <= 1'b0;
        end else begin
            if (push) wr_ptr <= wr_ptr + 1'b1;
            if (pop)  rd_ptr <= rd_ptr + 1'b1;

            // At most one net word in or out per cycle; a simultaneous push
            // and pop leaves the occupancy, and both flags, unchanged.
            if (push && !pop) begin
                level   <= level + 1'b1;
                empty_q <= 1'b0;
                full_q  <= (level == LVL_W'(DEPTH-1));
            end else if (pop && !push) begin
                level   <= level - 1'b1;
                full_q  <= 1'b0;
                empty_q <= (level == LVL_W'(1));
            end

            if (s_valid && !s_ready) overrun <= 1'b1;
        end
    end

    // synthesis translate_off
    initial begin
        if (DEPTH < 2 || (DEPTH & (DEPTH-1)) != 0)
            $fatal(1, "[elastic_fifo] DEPTH=%0d must be a power of two >= 2.", DEPTH);
    end
    // synthesis translate_on

endmodule
