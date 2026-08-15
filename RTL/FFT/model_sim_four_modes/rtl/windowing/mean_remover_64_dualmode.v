`timescale 1ns/1ps

// Remove a media de um frame serial de 64 amostras.
// A saida possui um bit de guarda e mantem os bits fracionarios da entrada:
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
    localparam STATE_COLLECT = 1'b0;
    localparam STATE_OUTPUT  = 1'b1;

    reg state;
    reg signed [SAMPLE_WIDTH-1:0] sample_memory [0:63];
    reg [5:0] write_index;
    reg [5:0] read_index;
    reg signed [SUM_WIDTH-1:0] sum_accumulator;
    reg signed [SAMPLE_WIDTH-1:0] mean_register;

    wire input_transfer;
    wire output_transfer;
    wire signed [SUM_WIDTH-1:0] input_extended;
    wire signed [SUM_WIDTH-1:0] sum_with_input;
    wire signed [SAMPLE_WIDTH:0] memory_sample_extended;
    wire signed [SAMPLE_WIDTH:0] mean_extended;

    assign frame_sample_ready = (state == STATE_COLLECT);
    assign corrected_sample_valid = (state == STATE_OUTPUT);
    assign corrected_sample_index = read_index;
    assign corrected_sample_first =
        corrected_sample_valid && (read_index == 6'd0);
    assign corrected_sample_last =
        corrected_sample_valid && (read_index == 6'd63);
    assign frame_mean = mean_register;
    assign frame_mean_valid = (state == STATE_OUTPUT);
    assign frame_busy = (state == STATE_OUTPUT);

    assign input_transfer = frame_sample_valid && frame_sample_ready;
    assign output_transfer =
        corrected_sample_valid && corrected_sample_ready;

    assign input_extended =
        {{(SUM_WIDTH-SAMPLE_WIDTH){frame_sample_in[SAMPLE_WIDTH-1]}},
         frame_sample_in};
    assign sum_with_input =
        $signed(sum_accumulator) + $signed(input_extended);
    assign memory_sample_extended =
        {sample_memory[read_index][SAMPLE_WIDTH-1],
         sample_memory[read_index]};
    assign mean_extended =
        {mean_register[SAMPLE_WIDTH-1], mean_register};
    assign corrected_sample_out =
        $signed(memory_sample_extended) - $signed(mean_extended);

    function automatic signed [SAMPLE_WIDTH-1:0] rounded_divide_64;
        input signed [SUM_WIDTH-1:0] value;
        reg signed [SUM_WIDTH:0] wide_value;
        reg signed [SUM_WIDTH:0] magnitude;
        reg signed [SUM_WIDTH:0] rounded_value;
        begin
            wide_value = {value[SUM_WIDTH-1], value};
            if (wide_value >= 0)
                rounded_value = (wide_value + 7'sd32) >>> 6;
            else begin
                magnitude = -wide_value;
                rounded_value = -((magnitude + 7'sd32) >>> 6);
            end
            rounded_divide_64 = rounded_value[SAMPLE_WIDTH-1:0];
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
                STATE_COLLECT: begin
                    if (input_transfer) begin
                        sample_memory[write_index] <= frame_sample_in;

                        if (write_index == 6'd63) begin
                            mean_register <= rounded_divide_64(sum_with_input);
                            sum_accumulator <= {SUM_WIDTH{1'b0}};
                            write_index <= 6'd0;
                            read_index <= 6'd0;
                            state <= STATE_OUTPUT;
                        end
                        else begin
                            sum_accumulator <= sum_with_input;
                            write_index <= write_index + 6'd1;
                        end
                    end
                end

                STATE_OUTPUT: begin
                    if (output_transfer) begin
                        if (read_index == 6'd63) begin
                            read_index <= 6'd0;
                            state <= STATE_COLLECT;
                        end
                        else
                            read_index <= read_index + 6'd1;
                    end
                end

                default: begin
                    state           <= STATE_COLLECT;
                    write_index     <= 6'd0;
                    read_index      <= 6'd0;
                    sum_accumulator <= {SUM_WIDTH{1'b0}};
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (SAMPLE_WIDTH <= 1)
            $fatal(1,
                "[mean_remover_64_dualmode] SAMPLE_WIDTH invalido.");
    end
`endif

endmodule
