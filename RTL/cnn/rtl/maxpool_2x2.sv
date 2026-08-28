`timescale 1ns / 1ps

module maxpool_2x2 #(
    parameter int DATA_WIDTH = 24,
    parameter int IMG_WIDTH = 32,
    parameter int CHANNELS = 8
)(
    input  logic               clk,
    input  logic               rst,
    
    // Stream Slave (from Conv2D)
    input  logic               s_valid,
    output logic               s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data [0:CHANNELS-1],
    input  logic               s_last,
    
    // Stream Master (to Flatten/Dense)
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data [0:CHANNELS-1],
    output logic               m_last
);

    localparam int DELAY_ROW = IMG_WIDTH;
    localparam int DELAY_ROW_PLUS_ONE = IMG_WIDTH + 1;

    // Shift registers for delaying lines. 
    logic signed [DATA_WIDTH-1:0] sr [0:CHANNELS-1][1:DELAY_ROW_PLUS_ONE];
    
    logic m_valid_reg;
    assign s_ready = m_ready || !m_valid_reg;
    
    logic [$clog2(IMG_WIDTH)-1:0] col;
    logic [$clog2(IMG_WIDTH)-1:0] row;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            col <= '0;
            row <= '0;
        end else if (s_valid && s_ready) begin
            if (col == IMG_WIDTH - 1) begin
                col <= '0;
                row <= row + 1'b1;
            end else begin
                col <= col + 1'b1;
            end
        end
    end

    // Shift register advancement
    always_ff @(posedge clk) begin
        if (s_valid && s_ready) begin
            for (int c = 0; c < CHANNELS; c++) begin
                sr[c][1] <= s_data[c];
                for (int d = 2; d <= DELAY_ROW_PLUS_ONE; d++) begin
                    sr[c][d] <= sr[c][d-1];
                end
            end
        end
    end

    // Output condition: We produce a maxpool output when at an odd column and odd row.
    // This perfectly isolates 2x2 non-overlapping windows (Stride = 2).
    logic is_output_cycle;
    assign is_output_cycle = s_valid && (col[0] == 1'b1) && (row[0] == 1'b1);

    // Registered output to break combinatorial critical paths
    logic signed [DATA_WIDTH-1:0] m_data_reg [0:CHANNELS-1];
    logic               m_last_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            m_valid_reg <= 1'b0;
            m_last_reg  <= 1'b0;
        end else if (s_ready) begin
            m_valid_reg <= is_output_cycle;
            m_last_reg  <= s_last && is_output_cycle;
            
            if (is_output_cycle) begin
                for (int c = 0; c < CHANNELS; c++) begin
                    // Extract the 4 pixels of the 2x2 window
                    logic signed [DATA_WIDTH-1:0] p_br;
                    logic signed [DATA_WIDTH-1:0] p_bl;
                    logic signed [DATA_WIDTH-1:0] p_tr;
                    logic signed [DATA_WIDTH-1:0] p_tl;
                    logic signed [DATA_WIDTH-1:0] max_b;
                    logic signed [DATA_WIDTH-1:0] max_t;
                    
                    p_br = s_data[c];
                    p_bl = sr[c][1];
                    p_tr = sr[c][DELAY_ROW];
                    p_tl = sr[c][DELAY_ROW_PLUS_ONE];
                    
                    // Cascaded comparators for the maximum
                    max_b = (p_br > p_bl) ? p_br : p_bl;
                    max_t = (p_tr > p_tl) ? p_tr : p_tl;
                    
                    m_data_reg[c] <= (max_b > max_t) ? max_b : max_t;
                end
            end
        end
    end

    assign m_valid = m_valid_reg;
    assign m_data  = m_data_reg;
    assign m_last  = m_last_reg;

endmodule
