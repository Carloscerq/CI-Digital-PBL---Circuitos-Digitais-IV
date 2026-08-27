`timescale 1ns/1ps

// Remove a media de um frame serial de 64 amostras.
//
// A memoria das amostras e implementada por dual_port_ram:
//   Quartus             -> altsyncram/M10K
//   ModelSim/Xcelium    -> modelo comportamental com RTL_SIM
//
// A saida possui um bit de guarda e preserva os bits fracionarios:
//   Q9.15  (24 bits) -> Q10.15 (25 bits)
//   Q11.16 (27 bits) -> Q12.16 (28 bits)
module mean_remover_64_dualmode #(
    parameter integer SAMPLE_WIDTH = 24
)(
    input  wire                            clk,
    input  wire                            reset,

    input  wire signed [SAMPLE_WIDTH-1:0]  frame_sample_in,
    input  wire                            frame_sample_valid,
    output wire                            frame_sample_ready,

    output wire signed [SAMPLE_WIDTH:0]    corrected_sample_out,
    output wire                            corrected_sample_valid,
    input  wire                            corrected_sample_ready,
    output wire [5:0]                      corrected_sample_index,
    output wire                            corrected_sample_first,
    output wire                            corrected_sample_last,

    output wire signed [SAMPLE_WIDTH-1:0]  frame_mean,
    output wire                            frame_mean_valid,
    output wire                            frame_busy
);

    localparam integer SUM_WIDTH = SAMPLE_WIDTH + 6;

    localparam [1:0] STATE_COLLECT = 2'd0;
    localparam [1:0] STATE_READ    = 2'd1;
    localparam [1:0] STATE_PRESENT = 2'd2;

    reg [1:0] state;

    reg [5:0] write_index;
    reg [5:0] read_index;

    reg signed [SUM_WIDTH-1:0]    sum_accumulator;
    reg signed [SAMPLE_WIDTH-1:0] mean_register;

    wire input_transfer;
    wire output_transfer;

    wire signed [SUM_WIDTH-1:0] input_extended;
    wire signed [SUM_WIDTH-1:0] sum_with_input;

    wire [SAMPLE_WIDTH-1:0] memory_read_data;
    wire [SAMPLE_WIDTH-1:0] memory_port_a_unused;

    wire signed [SAMPLE_WIDTH:0] memory_sample_extended;
    wire signed [SAMPLE_WIDTH:0] mean_extended;

    assign frame_sample_ready =
        (state == STATE_COLLECT);

    assign corrected_sample_valid =
        (state == STATE_PRESENT);

    assign corrected_sample_index = read_index;

    assign corrected_sample_first =
        corrected_sample_valid &&
        (read_index == 6'd0);

    assign corrected_sample_last =
        corrected_sample_valid &&
        (read_index == 6'd63);

    assign frame_mean = mean_register;

    // A media permanece valida durante toda a leitura do frame.
    assign frame_mean_valid =
        (state == STATE_READ) ||
        (state == STATE_PRESENT);

    assign frame_busy =
        (state != STATE_COLLECT);

    assign input_transfer =
        frame_sample_valid &&
        frame_sample_ready;

    assign output_transfer =
        corrected_sample_valid &&
        corrected_sample_ready;

    assign input_extended = {
        {(SUM_WIDTH-SAMPLE_WIDTH){
            frame_sample_in[SAMPLE_WIDTH-1]
        }},
        frame_sample_in
    };

    assign sum_with_input =
        $signed(sum_accumulator) +
        $signed(input_extended);

    assign memory_sample_extended = {
        memory_read_data[SAMPLE_WIDTH-1],
        memory_read_data
    };

    assign mean_extended = {
        mean_register[SAMPLE_WIDTH-1],
        mean_register
    };

    assign corrected_sample_out =
        $signed(memory_sample_extended) -
        $signed(mean_extended);

    // Porta A: escrita das 64 amostras.
    // Porta B: leitura sincrona para remocao da media.
    dual_port_ram #(
        .DATA_WIDTH (SAMPLE_WIDTH),
        .ADDR_WIDTH (6),
        .DEPTH      (64),
        .INIT_FILE  ("NONE")
    ) sample_memory (
        .clk        (clk),

        .we_a       (input_transfer),
        .addr_a     (write_index),
        .data_in_a  (frame_sample_in),
        .data_out_a (memory_port_a_unused),

        .we_b       (1'b0),
        .addr_b     (read_index),
        .data_in_b  ({SAMPLE_WIDTH{1'b0}}),
        .data_out_b (memory_read_data)
    );

    // Divisao por 64 com arredondamento simetrico.
    function automatic signed [SAMPLE_WIDTH-1:0]
        rounded_divide_64;

        input signed [SUM_WIDTH-1:0] value;

        reg signed [SUM_WIDTH:0] wide_value;
        reg signed [SUM_WIDTH:0] magnitude;
        reg signed [SUM_WIDTH:0] rounded_value;

        begin
            wide_value = {
                value[SUM_WIDTH-1],
                value
            };

            if (wide_value >= 0) begin
                rounded_value =
                    (wide_value + 7'sd32) >>> 6;
            end
            else begin
                magnitude = -wide_value;

                rounded_value =
                    -((magnitude + 7'sd32) >>> 6);
            end

            rounded_divide_64 =
                rounded_value[SAMPLE_WIDTH-1:0];
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state           <= STATE_COLLECT;
            write_index     <= 6'd0;
            read_index      <= 6'd0;
            sum_accumulator <= {SUM_WIDTH{1'b0}};
            mean_register   <= {SAMPLE_WIDTH{1'b0}};
        end
        else begin
            case (state)

                // Recebe e acumula as 64 amostras.
                STATE_COLLECT: begin
                    if (input_transfer) begin
                        if (write_index == 6'd63) begin
                            // sum_with_input inclui a amostra de indice 63.
                            mean_register <=
                                rounded_divide_64(sum_with_input);

                            sum_accumulator <=
                                {SUM_WIDTH{1'b0}};

                            write_index <= 6'd0;
                            read_index  <= 6'd0;

                            // Prepara a primeira leitura sincrona.
                            state <= STATE_READ;
                        end
                        else begin
                            sum_accumulator <= sum_with_input;
                            write_index <= write_index + 6'd1;
                        end
                    end
                end

                // Um ciclo para que o endereco seja registrado no M10K
                // e memory_read_data receba a amostra correspondente.
                STATE_READ: begin
                    state <= STATE_PRESENT;
                end

                // Mantem dado, indice e valid estaveis enquanto
                // corrected_sample_ready estiver desativado.
                STATE_PRESENT: begin
                    if (output_transfer) begin
                        if (read_index == 6'd63) begin
                            read_index <= 6'd0;
                            state <= STATE_COLLECT;
                        end
                        else begin
                            read_index <= read_index + 6'd1;
                            state <= STATE_READ;
                        end
                    end
                end

                default: begin
                    state           <= STATE_COLLECT;
                    write_index     <= 6'd0;
                    read_index      <= 6'd0;
                    sum_accumulator <= {SUM_WIDTH{1'b0}};
                    mean_register   <= {SAMPLE_WIDTH{1'b0}};
                end

            endcase
        end
    end

    // synthesis translate_off
    initial begin
        if (SAMPLE_WIDTH <= 1) begin
            $fatal(
                1,
                "[mean_remover_64_dualmode] SAMPLE_WIDTH invalido."
            );
        end
    end
    // synthesis translate_on

endmodule