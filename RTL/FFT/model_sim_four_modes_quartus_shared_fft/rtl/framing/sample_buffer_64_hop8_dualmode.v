`timescale 1ns/1ps

// Buffer circular para frames de 64 amostras.
//
// HOP_SIZE=64 por padrao: frames sem sobreposicao. O parametro continua
// configuravel entre 1 e 64 para preservar a compatibilidade com os testes
// anteriores.
//
// A memoria e acessada de forma sincrona por meio de dual_port_ram. No
// Quartus, dual_port_ram instancia uma altsyncram M10K; nos simuladores,
// quando RTL_SIM estiver definido, usa o modelo comportamental equivalente.
module sample_buffer_64_hop_dualmode #(
    parameter integer SAMPLE_WIDTH = 24,
    parameter integer HOP_SIZE     = 64
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

    localparam [1:0] STATE_FILL    = 2'd0;
    localparam [1:0] STATE_READ    = 2'd1;
    localparam [1:0] STATE_PRESENT = 2'd2;

    reg [1:0] state;
    reg [5:0] write_pointer;
    reg [5:0] frame_start_pointer;
    reg [6:0] valid_sample_count;
    reg [5:0] hop_counter;
    reg [5:0] read_offset;

    wire input_transfer;
    wire frame_transfer;
    wire [5:0] next_write_pointer;
    wire [5:0] frame_read_address;
    wire [SAMPLE_WIDTH-1:0] memory_read_data;
    wire [SAMPLE_WIDTH-1:0] memory_port_a_unused;

    assign next_write_pointer = write_pointer + 6'd1;
    assign frame_read_address = frame_start_pointer + read_offset;

    assign sample_ready       = (state == STATE_FILL);
    assign frame_sample_valid = (state == STATE_PRESENT);
    assign frame_sample_out   = $signed(memory_read_data);
    assign frame_sample_index = read_offset;
    assign frame_sample_first =
        frame_sample_valid && (read_offset == 6'd0);
    assign frame_sample_last =
        frame_sample_valid && (read_offset == 6'd63);
    assign buffer_full = (valid_sample_count == 7'd64);
    assign frame_busy  = (state != STATE_FILL);

    assign input_transfer = sample_valid && sample_ready;
    assign frame_transfer = frame_sample_valid && frame_sample_ready;

    // Porta A: escrita das amostras decimadas.
    // Porta B: leitura sincrona das amostras do frame.
    dual_port_ram #(
        .DATA_WIDTH (SAMPLE_WIDTH),
        .ADDR_WIDTH (6),
        .DEPTH      (64),
        .INIT_FILE  ("NONE")
    ) sample_memory (
        .clk        (clk),
        .we_a       (input_transfer),
        .addr_a     (write_pointer),
        .data_in_a  (sample_in),
        .data_out_a (memory_port_a_unused),
        .we_b       (1'b0),
        .addr_b     (frame_read_address),
        .data_in_b  ({SAMPLE_WIDTH{1'b0}}),
        .data_out_b (memory_read_data)
    );

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
                        write_pointer <= next_write_pointer;

                        if (valid_sample_count < 7'd64) begin
                            valid_sample_count <= valid_sample_count + 7'd1;

                            if (valid_sample_count == 7'd63) begin
                                // Depois da ultima escrita, o proximo ponteiro
                                // identifica a amostra mais antiga do frame.
                                frame_start_pointer <= next_write_pointer;
                                hop_counter <= 6'd0;
                                read_offset <= 6'd0;
                                state <= STATE_READ;
                            end
                        end
                        else begin
                            // Depois do primeiro frame, aguarda HOP_SIZE novas
                            // amostras antes de disponibilizar outro frame.
                            if (hop_counter == HOP_SIZE - 1) begin
                                frame_start_pointer <= next_write_pointer;
                                hop_counter <= 6'd0;
                                read_offset <= 6'd0;
                                state <= STATE_READ;
                            end
                            else begin
                                hop_counter <= hop_counter + 6'd1;
                            end
                        end
                    end
                end

                // Um ciclo para que o endereco seja registrado no M10K e o
                // dado correspondente apareca em memory_read_data.
                STATE_READ: begin
                    state <= STATE_PRESENT;
                end

                // Mantem dado, indice e valid estaveis durante backpressure.
                STATE_PRESENT: begin
                    if (frame_transfer) begin
                        if (read_offset == 6'd63) begin
                            read_offset <= 6'd0;
                            state <= STATE_FILL;
                        end
                        else begin
                            read_offset <= read_offset + 6'd1;
                            state <= STATE_READ;
                        end
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

    // synthesis translate_off
    initial begin
        if (SAMPLE_WIDTH <= 1)
            $fatal(1,
                "[sample_buffer_64_hop_dualmode] SAMPLE_WIDTH invalido.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1,
                "[sample_buffer_64_hop_dualmode] HOP_SIZE deve estar entre 1 e 64.");
    end
    // synthesis translate_on

endmodule
