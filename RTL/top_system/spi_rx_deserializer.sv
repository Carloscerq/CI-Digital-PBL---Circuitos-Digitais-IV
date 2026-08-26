// ============================================================================
// SPI RX Deserializer (8-bit to 24-bit)
// ============================================================================

module spi_rx_deserializer (
    input  logic        clk,
    input  logic        reset_n,
    input  logic [7:0]  spi_data,
    input  logic        spi_valid,
    output logic [23:0] out_data,
    output logic        out_valid,
    input  logic        out_ready
);
    logic [1:0] byte_cnt;
    logic [23:0] shift_reg;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            byte_cnt <= '0;
            shift_reg <= '0;
            out_valid <= 1'b0;
            out_data <= '0;
        end else begin
            if (out_valid && out_ready) begin
                out_valid <= 1'b0;
            end

            if (spi_valid) begin
                shift_reg <= {shift_reg[15:0], spi_data};
                if (byte_cnt == 2'd2) begin
                    byte_cnt <= '0;
                    out_data <= {shift_reg[15:0], spi_data};
                    out_valid <= 1'b1;
                end else begin
                    byte_cnt <= byte_cnt + 1'b1;
                end
            end
        end
    end
endmodule
