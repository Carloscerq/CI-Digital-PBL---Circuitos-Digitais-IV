`timescale 1ns / 1ps

// ============================================================================
// frame_pingpong_buffer -- 2D multi-channel frame double buffer (RAM based)
// ============================================================================
// Two RAM banks holding one complete FRAME_WORDS x CHANNELS image each. The
// producer fills one bank while the consumer streams the other out, so a
// consumer that takes many thousands of cycles per frame -- the CNN -- never
// backpressures the producer within a frame. A skid buffer cannot do this job:
// it holds two beats, not two frames.
//
// >>> PLACEMENT_NOTE <<<
// This sits DOWNSTREAM of the four spectrogram_generator instances, which
// carry ping-pong banks of their own. That is not a duplicate. The generators
// double-buffer each channel individually, ahead of the lockstep join; this
// buffer double-buffers the JOINED four-channel frame, so the joiner can drain
// all four generators at full rate the instant they are aligned, and release
// their read banks without waiting on the CNN at all.
//
// A frame is closed by `s_last` or by filling FRAME_WORDS words, whichever
// comes first.
//
// >>> STALL_NOTE <<<
// `stall_event` is sticky and latches when a beat is offered while both banks
// are occupied. NOTHING IS LOST when this fires: the producer here is a proper
// stream that holds its data, so the event means the CNN fell far enough
// behind to back-pressure the FFT -- two whole frames behind. That is the most
// useful thing this buffer can report, and it is the condition the Phase 4
// decoupling work exists to keep out of the FFT's flow control.
// ============================================================================
module frame_pingpong_buffer #(
    parameter int DATA_WIDTH  = 24,
    parameter int CHANNELS    = 4,
    parameter int FRAME_WORDS = 1024      // IMG_WIDTH * IMG_HEIGHT
)(
    input  logic clk,
    input  logic reset,                   // synchronous, active high

    // Stream slave: one co-located pixel per channel per beat
    input  logic                         s_valid,
    output logic                         s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data [0:CHANNELS-1],
    input  logic                         s_last,

    // Stream master: the same frame, to the CNN
    output logic                         m_valid,
    input  logic                         m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data [0:CHANNELS-1],
    output logic                         m_last,

    output logic                         stall_event
);

    localparam int BUS_W = CHANNELS * DATA_WIDTH;
    localparam int AW    = $clog2(FRAME_WORDS);

    (* ramstyle = "M10K" *) logic [BUS_W-1:0] bank0 [0:FRAME_WORDS-1];
    (* ramstyle = "M10K" *) logic [BUS_W-1:0] bank1 [0:FRAME_WORDS-1];

    logic [BUS_W-1:0] bank0_q, bank1_q;
    logic [BUS_W-1:0] wr_word, rd_word;

    logic          bank0_full, bank1_full;
    logic          wr_bank, rd_bank;
    logic [AW-1:0] wr_addr, rd_addr;
    logic          rd_run;

    logic s_xfer, wr_close, rd_close, out_free, ram_rd_en, rd_bank_ready;

    // ---- port packing ------------------------------------------------------
    genvar c;
    generate
        for (c = 0; c < CHANNELS; c++) begin : g_pack
            assign wr_word[c*DATA_WIDTH +: DATA_WIDTH] = s_data[c];
            assign m_data[c] = $signed(rd_word[c*DATA_WIDTH +: DATA_WIDTH]);
        end
    endgenerate

    assign rd_word = rd_bank ? bank1_q : bank0_q;

    // ========================================================================
    // Write side
    // ========================================================================
    assign s_ready  = wr_bank ? !bank1_full : !bank0_full;
    assign s_xfer   = s_valid && s_ready;
    assign wr_close = s_xfer && ((wr_addr == AW'(FRAME_WORDS-1)) || s_last);

    always_ff @(posedge clk) begin
        if (s_xfer && !wr_bank) bank0[wr_addr] <= wr_word;
        if (s_xfer &&  wr_bank) bank1[wr_addr] <= wr_word;

        // One read address feeds both banks; the occupied one is selected on
        // the output. Gating the enable holds the word during backpressure.
        if (ram_rd_en) begin
            bank0_q <= bank0[rd_addr];
            bank1_q <= bank1[rd_addr];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_bank       <= 1'b0;
            wr_addr       <= '0;
            stall_event <= 1'b0;
        end else begin
            if (s_xfer) begin
                if (wr_close) begin
                    wr_addr <= '0;
                    wr_bank <= ~wr_bank;
                end else begin
                    wr_addr <= wr_addr + 1'b1;
                end
            end
            if (s_valid && !s_ready) stall_event <= 1'b1;
        end
    end

    // ========================================================================
    // Read side
    // ========================================================================
    assign rd_bank_ready = rd_bank ? bank1_full : bank0_full;
    assign out_free      = !m_valid || m_ready;
    assign ram_rd_en     = rd_run && out_free;
    assign rd_close      = m_valid && m_ready && m_last;

    always_ff @(posedge clk) begin
        if (reset) begin
            rd_run  <= 1'b0;
            rd_bank <= 1'b0;
            rd_addr <= '0;
            m_valid <= 1'b0;
            m_last  <= 1'b0;
        end else begin
            if (ram_rd_en) begin
                // The word launched this cycle lands in bankN_q next cycle.
                m_valid <= 1'b1;
                m_last  <= (rd_addr == AW'(FRAME_WORDS-1));
                if (rd_addr == AW'(FRAME_WORDS-1)) rd_run  <= 1'b0;
                else                               rd_addr <= rd_addr + 1'b1;
            end else if (m_valid && m_ready) begin
                m_valid <= 1'b0;
                m_last  <= 1'b0;
            end

            if (rd_close) rd_bank <= ~rd_bank;

            // Start a frame only once the output slot has drained, so rd_addr
            // can never be reset out from under an in-flight read.
            if (!rd_run && !m_valid && rd_bank_ready) begin
                rd_run  <= 1'b1;
                rd_addr <= '0;
            end
        end
    end

    // ========================================================================
    // Bank occupancy
    // ========================================================================
    // Kept as two discrete bits rather than an array so the set and the clear
    // can never alias to the same element. They cannot collide in any case:
    // a bank is only filled while empty and only released while full.
    always_ff @(posedge clk) begin
        if (reset) begin
            bank0_full <= 1'b0;
            bank1_full <= 1'b0;
        end else begin
            if      (wr_close && !wr_bank) bank0_full <= 1'b1;
            else if (rd_close && !rd_bank) bank0_full <= 1'b0;

            if      (wr_close &&  wr_bank) bank1_full <= 1'b1;
            else if (rd_close &&  rd_bank) bank1_full <= 1'b0;
        end
    end

endmodule
