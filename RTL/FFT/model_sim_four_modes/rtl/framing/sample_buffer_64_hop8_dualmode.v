`timescale 1ns/1ps

// Buffer circular para frames de 64 amostras. O HOP_SIZE padrao e 8:
// em 800 Hz, cada novo frame e iniciado a cada 10 ms.
module sample_buffer_64_hop_dualmode #(
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer HOP_SIZE     = 8
)(
    input  wire                            clk,
    input  wire                            reset,
    input  wire signed [SAMPLE_WIDTH-1:0]  sample_in,
    input  wire                            sample_valid,
    output wire                            sample_ready,
    output wire signed [SAMPLE_WIDTH-1:0]  frame_sample_out,
    output wire                            frame_sample_valid,
    input  wire                            frame_sample_ready,
    output wire [5:0]                      frame_sample_index,
    output wire                            frame_sample_first,
    output wire                            frame_sample_last,
    output wire                            buffer_full,
    output wire                            frame_busy
);

    localparam STATE_FILL   = 1'b0;
    localparam STATE_STREAM = 1'b1;

    reg state;
    reg signed [SAMPLE_WIDTH-1:0] sample_memory [0:63];
    reg [5:0] write_pointer;
    reg [5:0] frame_start_pointer;
    reg [6:0] valid_sample_count;
    reg [5:0] hop_counter;
    reg [5:0] read_offset;

    wire input_transfer;
    wire frame_transfer;
    wire [5:0] next_write_pointer;
    wire [5:0] frame_read_address;

    assign next_write_pointer = write_pointer + 6'd1;
    assign frame_read_address = frame_start_pointer + read_offset;

    assign sample_ready = (state == STATE_FILL);
    assign frame_sample_valid = (state == STATE_STREAM);
    assign frame_sample_out = sample_memory[frame_read_address];
    assign frame_sample_index = read_offset;
    assign frame_sample_first =
        frame_sample_valid && (read_offset == 6'd0);
    assign frame_sample_last =
        frame_sample_valid && (read_offset == 6'd63);
    assign buffer_full = (valid_sample_count == 7'd64);
    assign frame_busy = (state == STATE_STREAM);

    assign input_transfer = sample_valid && sample_ready;
    assign frame_transfer = frame_sample_valid && frame_sample_ready;

    always @(posedge clk) begin
        if (reset) begin
            state               <= STATE_FILL;
            write_pointer       <= 6'd0;
            frame_start_pointer <= 6'd0;
            valid_sample_count  <= 7'd0;
            hop_counter         <= 6'd0;
            read_offset         <= 6'd0;
        end
        else begin
            case (state)
                STATE_FILL: begin
                    if (input_transfer) begin
                        sample_memory[write_pointer] <= sample_in;
                        write_pointer <= next_write_pointer;

                        if (valid_sample_count < 7'd64) begin
                            valid_sample_count <= valid_sample_count + 7'd1;

                            if (valid_sample_count == 7'd63) begin
                                // O ponteiro seguinte aponta para a amostra
                                // mais antiga do primeiro frame completo.
                                frame_start_pointer <= next_write_pointer;
                                hop_counter <= 6'd0;
                                read_offset <= 6'd0;
                                state <= STATE_STREAM;
                            end
                        end
                        else begin
                            // Depois do primeiro frame, somente HOP_SIZE
                            // amostras novas sao exigidas.
                            if (hop_counter == HOP_SIZE - 1) begin
                                frame_start_pointer <= next_write_pointer;
                                hop_counter <= 6'd0;
                                read_offset <= 6'd0;
                                state <= STATE_STREAM;
                            end
                            else
                                hop_counter <= hop_counter + 6'd1;
                        end
                    end
                end

                STATE_STREAM: begin
                    if (frame_transfer) begin
                        if (read_offset == 6'd63) begin
                            read_offset <= 6'd0;
                            state <= STATE_FILL;
                        end
                        else
                            read_offset <= read_offset + 6'd1;
                    end
                end

                default: begin
                    state               <= STATE_FILL;
                    write_pointer       <= 6'd0;
                    frame_start_pointer <= 6'd0;
                    valid_sample_count  <= 7'd0;
                    hop_counter         <= 6'd0;
                    read_offset         <= 6'd0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (SAMPLE_WIDTH <= 1)
            $fatal(1,
                "[sample_buffer_64_hop_dualmode] SAMPLE_WIDTH invalido.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1,
                "[sample_buffer_64_hop_dualmode] HOP_SIZE deve estar entre 1 e 64.");
    end
`endif

endmodule
