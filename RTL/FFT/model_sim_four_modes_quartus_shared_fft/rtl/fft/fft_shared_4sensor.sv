`timescale 1ns/1ps

// Escalonador round-robin para quatro frames seriais e uma unica FFT64.
// Cada entrada deve manter valid, sample, index e marcadores estaveis enquanto
// ready estiver desativado. Uma vez escolhido, um sensor permanece selecionado
// durante a carga, o processamento e a transmissao dos 64 bins.
module fft_shared_4sensor #(
    parameter integer DATA_WIDTH       = 24,
    parameter integer NORMALIZE        = 1,
    parameter integer COEFF_WIDTH      = 18,
    parameter integer TWIDDLE_FRAC_BITS = 17
)(
    input  wire                          clk,
    input  wire                          reset,

    input  wire signed [DATA_WIDTH-1:0] ch0_sample,
    input  wire                          ch0_valid,
    output wire                          ch0_ready,
    input  wire [5:0]                    ch0_index,
    input  wire                          ch0_first,
    input  wire                          ch0_last,
    input  wire                          ch0_saturated,

    input  wire signed [DATA_WIDTH-1:0] ch1_sample,
    input  wire                          ch1_valid,
    output wire                          ch1_ready,
    input  wire [5:0]                    ch1_index,
    input  wire                          ch1_first,
    input  wire                          ch1_last,
    input  wire                          ch1_saturated,

    input  wire signed [DATA_WIDTH-1:0] ch2_sample,
    input  wire                          ch2_valid,
    output wire                          ch2_ready,
    input  wire [5:0]                    ch2_index,
    input  wire                          ch2_first,
    input  wire                          ch2_last,
    input  wire                          ch2_saturated,

    input  wire signed [DATA_WIDTH-1:0] ch3_sample,
    input  wire                          ch3_valid,
    output wire                          ch3_ready,
    input  wire [5:0]                    ch3_index,
    input  wire                          ch3_first,
    input  wire                          ch3_last,
    input  wire                          ch3_saturated,

    output wire                          fft_valid,
    input  wire                          fft_ready,
    output wire [5:0]                    fft_bin,
    output wire signed [DATA_WIDTH-1:0] fft_real,
    output wire signed [DATA_WIDTH-1:0] fft_imag,
    output wire [1:0]                    fft_sensor_id,
    output wire                          fft_done,
    output wire                          fft_busy,

    output wire                          hann_saturation_event,
    output wire [1:0]                    hann_saturation_sensor_id,
    output wire                          fft_overflow_event,
    output wire [2:0]                    fft_overflow_stage,
    output wire [2:0]                    fft_overflow_components,
    output wire [1:0]                    fft_overflow_sensor_id
);

    localparam [1:0] STATE_SELECT = 2'd0;
    localparam [1:0] STATE_LOAD   = 2'd1;
    localparam [1:0] STATE_START  = 2'd2;
    localparam [1:0] STATE_WAIT   = 2'd3;

    reg [1:0] state;
    reg [1:0] selected_sensor;
    reg [1:0] round_robin_start;
    reg [1:0] candidate_sensor;
    reg candidate_valid;

    wire [3:0] channel_valids;
    assign channel_valids = {ch3_valid, ch2_valid, ch1_valid, ch0_valid};

    // Prioridade circular. A busca inicia no sensor seguinte ao ultimo frame
    // concluido, evitando que um canal continuamente valido monopolize a FFT.
    always @(*) begin
        candidate_sensor = round_robin_start;
        candidate_valid = 1'b1;
        case (round_robin_start)
            2'd0: begin
                if      (channel_valids[0]) candidate_sensor = 2'd0;
                else if (channel_valids[1]) candidate_sensor = 2'd1;
                else if (channel_valids[2]) candidate_sensor = 2'd2;
                else if (channel_valids[3]) candidate_sensor = 2'd3;
                else candidate_valid = 1'b0;
            end
            2'd1: begin
                if      (channel_valids[1]) candidate_sensor = 2'd1;
                else if (channel_valids[2]) candidate_sensor = 2'd2;
                else if (channel_valids[3]) candidate_sensor = 2'd3;
                else if (channel_valids[0]) candidate_sensor = 2'd0;
                else candidate_valid = 1'b0;
            end
            2'd2: begin
                if      (channel_valids[2]) candidate_sensor = 2'd2;
                else if (channel_valids[3]) candidate_sensor = 2'd3;
                else if (channel_valids[0]) candidate_sensor = 2'd0;
                else if (channel_valids[1]) candidate_sensor = 2'd1;
                else candidate_valid = 1'b0;
            end
            default: begin
                if      (channel_valids[3]) candidate_sensor = 2'd3;
                else if (channel_valids[0]) candidate_sensor = 2'd0;
                else if (channel_valids[1]) candidate_sensor = 2'd1;
                else if (channel_valids[2]) candidate_sensor = 2'd2;
                else candidate_valid = 1'b0;
            end
        endcase
    end

    reg signed [DATA_WIDTH-1:0] selected_sample;
    reg selected_valid;
    reg [5:0] selected_index;
    reg selected_first;
    reg selected_last;
    reg selected_saturated;

    always @(*) begin
        selected_sample = {DATA_WIDTH{1'b0}};
        selected_valid = 1'b0;
        selected_index = 6'd0;
        selected_first = 1'b0;
        selected_last = 1'b0;
        selected_saturated = 1'b0;
        case (selected_sensor)
            2'd0: begin
                selected_sample = ch0_sample;
                selected_valid = ch0_valid;
                selected_index = ch0_index;
                selected_first = ch0_first;
                selected_last = ch0_last;
                selected_saturated = ch0_saturated;
            end
            2'd1: begin
                selected_sample = ch1_sample;
                selected_valid = ch1_valid;
                selected_index = ch1_index;
                selected_first = ch1_first;
                selected_last = ch1_last;
                selected_saturated = ch1_saturated;
            end
            2'd2: begin
                selected_sample = ch2_sample;
                selected_valid = ch2_valid;
                selected_index = ch2_index;
                selected_first = ch2_first;
                selected_last = ch2_last;
                selected_saturated = ch2_saturated;
            end
            default: begin
                selected_sample = ch3_sample;
                selected_valid = ch3_valid;
                selected_index = ch3_index;
                selected_first = ch3_first;
                selected_last = ch3_last;
                selected_saturated = ch3_saturated;
            end
        endcase
    end

    wire fft_load_ready;
    wire fft_core_busy;
    wire fft_start;
    wire load_transfer;

    assign ch0_ready = (state == STATE_LOAD) &&
                       (selected_sensor == 2'd0) && fft_load_ready;
    assign ch1_ready = (state == STATE_LOAD) &&
                       (selected_sensor == 2'd1) && fft_load_ready;
    assign ch2_ready = (state == STATE_LOAD) &&
                       (selected_sensor == 2'd2) && fft_load_ready;
    assign ch3_ready = (state == STATE_LOAD) &&
                       (selected_sensor == 2'd3) && fft_load_ready;

    assign load_transfer = (state == STATE_LOAD) &&
                           selected_valid && fft_load_ready;
    assign fft_start = (state == STATE_START);

    always @(posedge clk) begin
        if (reset) begin
            state <= STATE_SELECT;
            selected_sensor <= 2'd0;
            round_robin_start <= 2'd0;
        end
        else begin
            case (state)
                STATE_SELECT: begin
                    if (candidate_valid) begin
                        selected_sensor <= candidate_sensor;
                        state <= STATE_LOAD;
                    end
                end

                STATE_LOAD: begin
                    if (load_transfer && selected_last)
                        state <= STATE_START;
                end

                STATE_START: state <= STATE_WAIT;

                STATE_WAIT: begin
                    if (fft_done) begin
                        round_robin_start <= selected_sensor + 2'd1;
                        state <= STATE_SELECT;
                    end
                end

                default: begin
                    state <= STATE_SELECT;
                    selected_sensor <= 2'd0;
                    round_robin_start <= 2'd0;
                end
            endcase
        end
    end

    fft_64_dualmode #(
        .INPUT_WIDTH       (DATA_WIDTH),
        .FFT_WIDTH         (DATA_WIDTH),
        .COEFF_WIDTH       (COEFF_WIDTH),
        .TWIDDLE_FRAC_BITS (TWIDDLE_FRAC_BITS),
        .NORMALIZE         (NORMALIZE)
    ) fft_core (
        .clk                       (clk),
        .reset                     (reset),
        .load_en                   (load_transfer),
        .load_addr                 (selected_index),
        .load_data                 (selected_sample),
        .load_ready                (fft_load_ready),
        .start                     (fft_start),
        .busy                      (fft_core_busy),
        .done                      (fft_done),
        .fft_valid                 (fft_valid),
        .fft_ready                 (fft_ready),
        .fft_bin_out               (fft_bin),
        .fft_real_out              (fft_real),
        .fft_imag_out              (fft_imag),
        .overflow_event            (fft_overflow_event),
        .overflow_stage            (fft_overflow_stage),
        .overflow_components       (fft_overflow_components),
        .overflow_total_components (),
        .probe_event               (),
        .probe_stage               (),
        .probe_top_real            (),
        .probe_top_imag            (),
        .probe_bottom_real         (),
        .probe_bottom_imag         ()
    );

    assign fft_sensor_id = selected_sensor;
    assign hann_saturation_event = load_transfer && selected_saturated;
    assign hann_saturation_sensor_id = selected_sensor;
    assign fft_overflow_sensor_id = selected_sensor;
    assign fft_busy = fft_core_busy || (state != STATE_SELECT);

    // synthesis translate_off
    reg [6:0] loaded_count;
    always @(posedge clk) begin
        if (reset || state == STATE_SELECT)
            loaded_count <= 7'd0;
        else if (load_transfer) begin
            if ((loaded_count == 0) &&
                (!selected_first || selected_index != 6'd0))
                $fatal(1, "[fft_shared_4sensor] Inicio de frame invalido.");
            if (selected_index != loaded_count[5:0])
                $fatal(1, "[fft_shared_4sensor] Indice de carga invalido.");
            if (selected_last !== (selected_index == 6'd63))
                $fatal(1, "[fft_shared_4sensor] Marcador last invalido.");
            loaded_count <= loaded_count + 7'd1;
        end
    end
    // synthesis translate_on

endmodule
