`timescale 1ns / 1ps

// ============================================================================
// Spectrogram generator
// ============================================================================
// Ping-pong M10K buffer between the FFT and the CNN. Both ports use the same
// plain handshake: a beat transfers when valid and ready are both high on a
// rising clock edge; `last` closes the current buffer on the write side and
// marks the final word of a spectrogram on the read side.
// ============================================================================
module spectrogram_generator #(
    parameter int DATA_WIDTH = 24,
    parameter int BINS_PER_FRAME = 32,
    parameter int FRAMES_PER_SPECTROGRAM = 32
)(
    input  logic                      clk,
    input  logic                      reset,
    
    // Stream slave: bins from the FFT
    input  logic                      s_valid,
    output logic                      s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data,
    input  logic                      s_last,
    
    // Stream master: whole spectrogram to the CNN
    output logic                      m_valid,
    input  logic                      m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data,
    output logic                      m_last
);

    localparam int MEM_DEPTH = BINS_PER_FRAME * FRAMES_PER_SPECTROGRAM;
    localparam int ADDR_WIDTH = $clog2(MEM_DEPTH);

    // M10K Ping-Pong Buffers
    (* ramstyle = "M10K" *) logic signed [DATA_WIDTH-1:0] ram_0 [0:MEM_DEPTH-1];
    (* ramstyle = "M10K" *) logic signed [DATA_WIDTH-1:0] ram_1 [0:MEM_DEPTH-1];

    logic signed [DATA_WIDTH-1:0] ram_0_out;
    logic signed [DATA_WIDTH-1:0] ram_1_out;

    logic wr_side; // 0: Write to ram_0, 1: Write to ram_1
    logic rd_side; // 0: Read from ram_0, 1: Read from ram_1
    
    logic buf_0_ready_to_read;
    logic buf_1_ready_to_read;

    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [ADDR_WIDTH-1:0] rd_count;
    logic rd_active;

    // =========================================================================
    // WRITE LOGIC (FFT -> RAM)
    // =========================================================================
    
    // We are ready to accept data if the current write-side buffer is not full 
    // and waiting to be read.
    assign s_ready = (wr_side == 1'b0) ? !buf_0_ready_to_read : !buf_1_ready_to_read;
    
    logic ram_0_wr_en;
    logic ram_1_wr_en;
    logic ram_rd_en;
    
    assign ram_0_wr_en = (s_valid && s_ready) && (wr_side == 1'b0);
    assign ram_1_wr_en = (s_valid && s_ready) && (wr_side == 1'b1);
    
    // The BRAM output should only update if the output is empty (!m_valid)
    // or if the downstream consumer successfully consumes the current data (m_ready).
    assign ram_rd_en = (!m_valid || m_ready);

    always_ff @(posedge clk) begin
        if (ram_0_wr_en) ram_0[wr_addr] <= s_data;
        if (ram_1_wr_en) ram_1[wr_addr] <= s_data;
        
        // Read address feeds both RAMs, gated by read enable to handle backpressure flawlessly
        if (ram_rd_en) begin
            ram_0_out <= ram_0[rd_addr];
            ram_1_out <= ram_1[rd_addr];
        end
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            wr_side <= 1'b0;
            buf_0_ready_to_read <= 1'b0;
            buf_1_ready_to_read <= 1'b0;
            wr_addr <= '0;
        end else begin
            // 1. Write Side Management
            if (s_valid && s_ready) begin
                if ((wr_addr == MEM_DEPTH - 1) || s_last) begin
                    // Buffer is full (or forcefully finished by last signal)
                    wr_addr <= '0;
                    if (wr_side == 1'b0) begin
                        buf_0_ready_to_read <= 1'b1;
                        wr_side <= 1'b1; // Swap write focus to Buffer 1
                    end else begin
                        buf_1_ready_to_read <= 1'b1;
                        wr_side <= 1'b0; // Swap write focus to Buffer 0
                    end
                end else begin
                    wr_addr <= wr_addr + 1'b1;
                end
            end
            
            // 2. Read Side clears the ready flags when finishing a buffer read
            if (m_valid && m_ready && m_last) begin
                if (rd_side == 1'b0) begin
                    buf_0_ready_to_read <= 1'b0;
                end else begin
                    buf_1_ready_to_read <= 1'b0;
                end
            end
        end
    end

    // =========================================================================
    // READ LOGIC (RAM -> CNN)
    // =========================================================================
    
    logic active_rd_ready;
    assign active_rd_ready = (rd_side == 1'b0) ? buf_0_ready_to_read : buf_1_ready_to_read;

    always_ff @(posedge clk) begin
        if (reset) begin
            rd_side <= 1'b0;
            rd_active <= 1'b0;
            m_valid <= 1'b0;
            m_last <= 1'b0;
            rd_addr <= '0;
            rd_count <= '0;
        end else begin
            // Toggle read side when a full spectrogram is consumed
            if (m_valid && m_ready && m_last) begin
                rd_side <= ~rd_side;
            end
            
            if (rd_active) begin
                // Proceed if output is idle or consumer is ready for the current word
                if (!m_valid || m_ready) begin
                    m_valid <= 1'b1;
                    
                    if (rd_count == MEM_DEPTH - 1) begin
                        m_last <= 1'b1;
                        rd_active <= 1'b0; // End of read sequence
                    end else begin
                        m_last <= 1'b0;
                        rd_count <= rd_count + 1'b1;
                        rd_addr <= rd_addr + 1'b1; // Pre-fetch next address
                    end
                end
            end else begin
                // When completely idle (valid cleared), check if the active read buffer is ready
                if (!m_valid) begin
                    if (active_rd_ready) begin
                        rd_active <= 1'b1;
                        rd_addr <= '0;
                        rd_count <= '0;
                    end
                end
            end
            
            // Handshake clears the valid/last signal if the sequence has finished (rd_active == 0)
            if (m_valid && m_ready && !rd_active) begin
                m_valid <= 1'b0;
                m_last <= 1'b0;
            end
        end
    end
    
    // Select the output data based on the current active read side
    assign m_data = (rd_side == 1'b0) ? ram_0_out : ram_1_out;

endmodule
