module uart_tx #(
    parameter CLOCK_FREQ = 50_000_000,
    parameter BAUD_RATE  = 115_200
)(
    input  wire       clk,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy
);

    localparam integer CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;

    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0] state = IDLE;

    reg [15:0] clk_count = 0;
    reg [2:0]  bit_index = 0;
    reg [7:0]  data_reg  = 0;

    initial begin
        tx   = 1'b1;
        busy = 1'b0;
    end

    always @(posedge clk) begin

        case (state)
            
            // UART parada            
            IDLE: begin

                tx        <= 1'b1;
                busy      <= 1'b0;
                clk_count <= 0;
                bit_index <= 0;

                if (start) begin
                    data_reg <= data;
                    busy     <= 1'b1;
                    state    <= START;
                end
            end


            
            // Start bit
            START: begin

                tx <= 1'b0;

                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    state     <= DATA;
                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end
            end


            
            // 8 bits de dados
            // UART transmite LSB primeiro
            
            DATA: begin

                tx <= data_reg[bit_index];

                if (clk_count == CLKS_PER_BIT - 1) begin

                    clk_count <= 0;

                    if (bit_index == 7) begin
                        bit_index <= 0;
                        state     <= STOP;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                    end
                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end
            end


            
            // Stop bit
            
            STOP: begin

                tx <= 1'b1;

                if (clk_count == CLKS_PER_BIT - 1) begin
                    clk_count <= 0;
                    busy      <= 1'b0;
                    state     <= IDLE;
                end
                else begin
                    clk_count <= clk_count + 1'b1;
                end
            end


            default: begin
                state <= IDLE;
                tx    <= 1'b1;
                busy  <= 1'b0;
            end

        endcase

    end

endmodule