`timescale 1ns / 1ps

module line_buffer_3x3 #(
    parameter int DATA_WIDTH = 24,
    parameter int IMG_WIDTH  = 32,
    parameter int IMG_HEIGHT = 32
)(
    input  logic               clk,
    input  logic               rst,
    
    // AXI4-Stream slave interface (Input Pixels)
    input  logic               s_valid,
    output logic               s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data,
    input  logic               s_last,
    
    // AXI4-Stream master interface (Output 3x3 Window)
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [DATA_WIDTH-1:0] m_window [0:2][0:2],
    output logic               m_last
);

    // Image dimensions and padded dimensions
    localparam int PAD_WIDTH  = IMG_WIDTH + 2;  
    localparam int PAD_HEIGHT = IMG_HEIGHT + 2; 

    // Counters to track position in the padded grid
    logic [$clog2(PAD_WIDTH)-1:0] px;
    logic [$clog2(PAD_HEIGHT)-1:0] py;

    // Check if current coordinate is inside the active image area (1 to 32)
    logic is_active_pixel;
    assign is_active_pixel = (px >= 1 && px <= IMG_WIDTH) && (py >= 1 && py <= IMG_HEIGHT);

    // Handshaking logic
    // We advance if the consumer is ready AND we either have valid data (if active pixel) 
    // or we are in the padding region (auto-advance without needing valid input data).
    logic advance;
    assign advance = m_ready && (!is_active_pixel || s_valid);

    // The line buffer can accept data if it's advancing and currently on an active pixel
    assign s_ready = advance && is_active_pixel;

    // Coordinate tracking
    always_ff @(posedge clk) begin
        if (rst) begin
            px <= '0;
            py <= '0;
        end else if (advance) begin
            if (px == PAD_WIDTH - 1) begin
                px <= '0;
                if (py == PAD_HEIGHT - 1) begin
                    py <= '0;
                end else begin
                    py <= py + 1'b1;
                end
            end else begin
                px <= px + 1'b1;
            end
        end
    end

    // Select input data or 0 for padding
    logic signed [DATA_WIDTH-1:0] current_pixel;
    assign current_pixel = is_active_pixel ? s_data : '0;

    // Shift registers for line buffering (length PAD_WIDTH maps to SRLs in FPGA)
    logic signed [DATA_WIDTH-1:0] shift_reg1 [0:PAD_WIDTH-1];
    logic signed [DATA_WIDTH-1:0] shift_reg2 [0:PAD_WIDTH-1];

    always_ff @(posedge clk) begin
        // No reset for shift registers to ensure SRL inference
        if (advance) begin
            for (int i = PAD_WIDTH - 1; i > 0; i--) begin
                shift_reg1[i] <= shift_reg1[i-1];
                shift_reg2[i] <= shift_reg2[i-1];
            end
            shift_reg1[0] <= current_pixel;
            shift_reg2[0] <= shift_reg1[PAD_WIDTH-1];
        end
    end

    // 3x3 Window construction
    always_ff @(posedge clk) begin
        if (rst) begin
            for (int r = 0; r < 3; r++) begin
                for (int c = 0; c < 3; c++) begin
                    m_window[r][c] <= '0;
                end
            end
        end else if (advance) begin
            // Row 0 (Top row of the window)
            m_window[0][0] <= m_window[0][1];
            m_window[0][1] <= m_window[0][2];
            m_window[0][2] <= shift_reg2[PAD_WIDTH-1];

            // Row 1 (Middle row of the window)
            m_window[1][0] <= m_window[1][1];
            m_window[1][1] <= m_window[1][2];
            m_window[1][2] <= shift_reg1[PAD_WIDTH-1];

            // Row 2 (Bottom row of the window)
            m_window[2][0] <= m_window[2][1];
            m_window[2][1] <= m_window[2][2];
            m_window[2][2] <= current_pixel;
        end
    end

    // Valid and Last signal generation for the output stream
    // The center of the 3x3 window will be valid 36 cycles after the current pixel.
    // However, by looking at the delayed coordinate (px, py), we can combinatorially 
    // determine if the resulting window next cycle is valid.
    logic is_center_valid;
    assign is_center_valid = (px >= 2 && px <= PAD_WIDTH - 1) && (py >= 2 && py <= PAD_HEIGHT - 1);

    logic m_valid_reg;
    logic m_last_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            m_valid_reg <= 1'b0;
            m_last_reg  <= 1'b0;
        end else if (advance) begin
            m_valid_reg <= is_center_valid;
            // Last pixel of the padded frame indicates the end of the entire valid stream
            m_last_reg  <= (px == PAD_WIDTH - 1) && (py == PAD_HEIGHT - 1);
        end
    end

    assign m_valid = m_valid_reg;
    assign m_last  = m_last_reg;

endmodule
