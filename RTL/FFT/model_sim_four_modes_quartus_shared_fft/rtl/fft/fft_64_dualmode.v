// FFT64 radix-2 DIF parametrizavel para os dois experimentos do PBL-FFT.
//
// NORMALIZE = 1: divide por 2 em cada estagio e entrega DFT/64 (Q9.15).
// NORMALIZE = 0: nao escala e satura na largura escolhida (Q11.16).
// A interface de overflow informa qualquer componente limitado pelo datapath.
//
// Twiddles remain signed Q1.17. The output bins are returned in natural order.
// As memorias real/imag usam leitura sincrona de um ciclo. Em sintese, o
// wrapper dual_port_ram instancia M10K; em simulacao, RTL_SIM seleciona o
// modelo Verilog portavel com a mesma latencia observavel pela maquina de estados.
module fft_64_dualmode #(
    parameter INPUT_WIDTH = 24,
    parameter FFT_WIDTH = 24,
    parameter COEFF_WIDTH = 18,
    parameter TWIDDLE_FRAC_BITS = 17,
    parameter NORMALIZE = 1
)(
    input wire clk,
    input wire reset,
    input wire load_en,
    input wire [5:0] load_addr,
    input wire signed [INPUT_WIDTH-1:0] load_data,
    output wire load_ready,
    input wire start,
    output reg busy,
    output reg done,
    output reg fft_valid,
    input wire fft_ready,
    output reg [5:0] fft_bin_out,
    output reg signed [FFT_WIDTH-1:0] fft_real_out,
    output reg signed [FFT_WIDTH-1:0] fft_imag_out,
    output reg overflow_event,
    output reg [2:0] overflow_stage,
    output reg [2:0] overflow_components,
    output reg [31:0] overflow_total_components,
    output reg probe_event,
    output reg [2:0] probe_stage,
    output reg signed [FFT_WIDTH-1:0] probe_top_real,
    output reg signed [FFT_WIDTH-1:0] probe_top_imag,
    output reg signed [FFT_WIDTH-1:0] probe_bottom_real,
    output reg signed [FFT_WIDTH-1:0] probe_bottom_imag
);

    localparam DIFF_WIDTH = FFT_WIDTH + 1;
    localparam PROD_WIDTH = DIFF_WIDTH + COEFF_WIDTH;
    localparam MULT_WIDTH = PROD_WIDTH + 1;

    localparam S_IDLE = 3'd0;
    localparam S_READ = 3'd1;
    localparam S_WAIT = 3'd2;
    localparam S_WRITE = 3'd3;
    localparam S_OUT_READ = 3'd4;
    localparam S_OUT_WAIT = 3'd5;
    localparam S_OUT_HOLD = 3'd6;
    localparam S_DONE = 3'd7;

    reg [2:0] state;
    reg [2:0] stage_count;
    reg [4:0] butterfly_count;
    reg [5:0] output_count;
    reg [5:0] addr_a_saved;
    reg [5:0] addr_b_saved;

    reg signed [FFT_WIDTH-1:0] operand_a_real;
    reg signed [FFT_WIDTH-1:0] operand_a_imag;
    reg signed [FFT_WIDTH-1:0] operand_b_real;
    reg signed [FFT_WIDTH-1:0] operand_b_imag;
    reg signed [COEFF_WIDTH-1:0] twiddle_real_saved;
    reg signed [COEFF_WIDTH-1:0] twiddle_imag_saved;

    reg [5:0] addr_a_calc;
    reg [5:0] addr_b_calc;
    reg [4:0] twiddle_addr_calc;

    always @(*) begin
        addr_a_calc = 6'd0;
        addr_b_calc = 6'd0;
        twiddle_addr_calc = 5'd0;
        case (stage_count)
            3'd0: begin
                addr_a_calc = {1'b0, butterfly_count};
                addr_b_calc = {1'b0, butterfly_count} + 6'd32;
                twiddle_addr_calc = butterfly_count;
            end
            3'd1: begin
                addr_a_calc = {butterfly_count[4], 1'b0, butterfly_count[3:0]};
                addr_b_calc = addr_a_calc + 6'd16;
                twiddle_addr_calc = {butterfly_count[3:0], 1'b0};
            end
            3'd2: begin
                addr_a_calc = {butterfly_count[4:3], 1'b0, butterfly_count[2:0]};
                addr_b_calc = addr_a_calc + 6'd8;
                twiddle_addr_calc = {butterfly_count[2:0], 2'b00};
            end
            3'd3: begin
                addr_a_calc = {butterfly_count[4:2], 1'b0, butterfly_count[1:0]};
                addr_b_calc = addr_a_calc + 6'd4;
                twiddle_addr_calc = {butterfly_count[1:0], 3'b000};
            end
            3'd4: begin
                addr_a_calc = {butterfly_count[4:1], 1'b0, butterfly_count[0]};
                addr_b_calc = addr_a_calc + 6'd2;
                twiddle_addr_calc = {butterfly_count[0], 4'b0000};
            end
            default: begin
                addr_a_calc = {butterfly_count, 1'b0};
                addr_b_calc = {butterfly_count, 1'b0} + 6'd1;
                twiddle_addr_calc = 5'd0;
            end
        endcase
    end

    wire signed [COEFF_WIDTH-1:0] twiddle_real_wire;
    wire signed [COEFF_WIDTH-1:0] twiddle_imag_wire;

    fft_twiddle_rom_64 twiddle_rom (
        .address(twiddle_addr_calc),
        .twiddle_real(twiddle_real_wire),
        .twiddle_imag(twiddle_imag_wire)
    );

    wire signed [DIFF_WIDTH-1:0] sum_real_full;
    wire signed [DIFF_WIDTH-1:0] sum_imag_full;
    wire signed [DIFF_WIDTH-1:0] diff_real_full;
    wire signed [DIFF_WIDTH-1:0] diff_imag_full;

    assign sum_real_full =
        $signed({operand_a_real[FFT_WIDTH-1], operand_a_real}) +
        $signed({operand_b_real[FFT_WIDTH-1], operand_b_real});
    assign sum_imag_full =
        $signed({operand_a_imag[FFT_WIDTH-1], operand_a_imag}) +
        $signed({operand_b_imag[FFT_WIDTH-1], operand_b_imag});
    assign diff_real_full =
        $signed({operand_a_real[FFT_WIDTH-1], operand_a_real}) -
        $signed({operand_b_real[FFT_WIDTH-1], operand_b_real});
    assign diff_imag_full =
        $signed({operand_a_imag[FFT_WIDTH-1], operand_a_imag}) -
        $signed({operand_b_imag[FFT_WIDTH-1], operand_b_imag});

    wire signed [PROD_WIDTH-1:0] product_rr;
    wire signed [PROD_WIDTH-1:0] product_ii;
    wire signed [PROD_WIDTH-1:0] product_ri;
    wire signed [PROD_WIDTH-1:0] product_ir;
    assign product_rr = diff_real_full * twiddle_real_saved;
    assign product_ii = diff_imag_full * twiddle_imag_saved;
    assign product_ri = diff_real_full * twiddle_imag_saved;
    assign product_ir = diff_imag_full * twiddle_real_saved;

    wire signed [MULT_WIDTH-1:0] bottom_real_full;
    wire signed [MULT_WIDTH-1:0] bottom_imag_full;
    assign bottom_real_full =
        $signed({product_rr[PROD_WIDTH-1], product_rr}) -
        $signed({product_ii[PROD_WIDTH-1], product_ii});
    assign bottom_imag_full =
        $signed({product_ri[PROD_WIDTH-1], product_ri}) +
        $signed({product_ir[PROD_WIDTH-1], product_ir});

    function automatic signed [MULT_WIDTH:0] round_product_full;
        input signed [MULT_WIDTH-1:0] value;
        input integer shift_bits;
        reg signed [MULT_WIDTH:0] value_ext;
        reg [MULT_WIDTH:0] magnitude;
        reg [MULT_WIDTH:0] rounded_magnitude;
        begin
            value_ext = {value[MULT_WIDTH-1], value};
            magnitude = {(MULT_WIDTH+1){1'b0}};
            rounded_magnitude = {(MULT_WIDTH+1){1'b0}};
            round_product_full = {(MULT_WIDTH+1){1'b0}};
            if (value_ext < 0) begin
                magnitude = -value_ext;
                rounded_magnitude = magnitude +
                    ({{MULT_WIDTH{1'b0}}, 1'b1} << (shift_bits-1));
                round_product_full = -$signed(rounded_magnitude >> shift_bits);
            end else begin
                rounded_magnitude = value_ext +
                    ({{MULT_WIDTH{1'b0}}, 1'b1} << (shift_bits-1));
                round_product_full = $signed(rounded_magnitude >> shift_bits);
            end
        end
    endfunction

    function signed [FFT_WIDTH-1:0] saturate_diff;
        input signed [DIFF_WIDTH-1:0] value;
        reg signed [DIFF_WIDTH-1:0] max_value;
        reg signed [DIFF_WIDTH-1:0] min_value;
        begin
            max_value = {{(DIFF_WIDTH-FFT_WIDTH){1'b0}},
                         1'b0, {(FFT_WIDTH-1){1'b1}}};
            min_value = {{(DIFF_WIDTH-FFT_WIDTH){1'b1}},
                         1'b1, {(FFT_WIDTH-1){1'b0}}};
            if (value > max_value)
                saturate_diff = {1'b0, {(FFT_WIDTH-1){1'b1}}};
            else if (value < min_value)
                saturate_diff = {1'b1, {(FFT_WIDTH-1){1'b0}}};
            else
                saturate_diff = value[FFT_WIDTH-1:0];
        end
    endfunction

    function signed [FFT_WIDTH-1:0] saturate_product;
        input signed [MULT_WIDTH:0] value;
        reg signed [MULT_WIDTH:0] max_value;
        reg signed [MULT_WIDTH:0] min_value;
        begin
            max_value = {{(MULT_WIDTH+1-FFT_WIDTH){1'b0}},
                         1'b0, {(FFT_WIDTH-1){1'b1}}};
            min_value = {{(MULT_WIDTH+1-FFT_WIDTH){1'b1}},
                         1'b1, {(FFT_WIDTH-1){1'b0}}};
            if (value > max_value)
                saturate_product = {1'b0, {(FFT_WIDTH-1){1'b1}}};
            else if (value < min_value)
                saturate_product = {1'b1, {(FFT_WIDTH-1){1'b0}}};
            else
                saturate_product = value[FFT_WIDTH-1:0];
        end
    endfunction

    function automatic signed [FFT_WIDTH-1:0] round_half_sum;
        input signed [DIFF_WIDTH-1:0] value;
        reg signed [DIFF_WIDTH:0] value_ext;
        reg [DIFF_WIDTH:0] magnitude;
        reg signed [DIFF_WIDTH:0] rounded_half;
        begin
            value_ext = {value[DIFF_WIDTH-1], value};
            magnitude = {(DIFF_WIDTH+1){1'b0}};
            rounded_half = {(DIFF_WIDTH+1){1'b0}};
            if (value_ext < 0) begin
                magnitude = -value_ext;
                rounded_half =
                    -$signed((magnitude +
                        {{DIFF_WIDTH{1'b0}}, 1'b1}) >> 1);
            end else begin
                rounded_half =
                    $signed((value_ext +
                        {{DIFF_WIDTH{1'b0}}, 1'b1}) >>> 1);
            end
            // A divisao por dois garante que o resultado cabe em FFT_WIDTH.
            // O slice torna o corte intencional e evita truncamento implicito.
            round_half_sum = rounded_half[FFT_WIDTH-1:0];
        end
    endfunction

    wire signed [MULT_WIDTH:0] bottom_real_scaled_normalized;
    wire signed [MULT_WIDTH:0] bottom_imag_scaled_normalized;
    wire signed [MULT_WIDTH:0] bottom_real_scaled_nonorm;
    wire signed [MULT_WIDTH:0] bottom_imag_scaled_nonorm;

    assign bottom_real_scaled_normalized =
        round_product_full(bottom_real_full, TWIDDLE_FRAC_BITS + 1);
    assign bottom_imag_scaled_normalized =
        round_product_full(bottom_imag_full, TWIDDLE_FRAC_BITS + 1);
    assign bottom_real_scaled_nonorm =
        round_product_full(bottom_real_full, TWIDDLE_FRAC_BITS);
    assign bottom_imag_scaled_nonorm =
        round_product_full(bottom_imag_full, TWIDDLE_FRAC_BITS);

    wire signed [DIFF_WIDTH-1:0] diff_max_q;
    wire signed [DIFF_WIDTH-1:0] diff_min_q;
    wire signed [MULT_WIDTH:0] product_max_q;
    wire signed [MULT_WIDTH:0] product_min_q;
    assign diff_max_q = {{(DIFF_WIDTH-FFT_WIDTH){1'b0}},
                         1'b0, {(FFT_WIDTH-1){1'b1}}};
    assign diff_min_q = {{(DIFF_WIDTH-FFT_WIDTH){1'b1}},
                         1'b1, {(FFT_WIDTH-1){1'b0}}};
    assign product_max_q = {{(MULT_WIDTH+1-FFT_WIDTH){1'b0}},
                            1'b0, {(FFT_WIDTH-1){1'b1}}};
    assign product_min_q = {{(MULT_WIDTH+1-FFT_WIDTH){1'b1}},
                            1'b1, {(FFT_WIDTH-1){1'b0}}};

    wire overflow_top_real;
    wire overflow_top_imag;
    wire overflow_bottom_real;
    wire overflow_bottom_imag;
    // As somas normalizadas sempre cabem depois da divisao por 2. Nos ramos
    // com twiddle, verifica-se o valor efetivamente selecionado antes do corte.
    assign overflow_top_real = !NORMALIZE &&
        ((sum_real_full > diff_max_q) || (sum_real_full < diff_min_q));
    assign overflow_top_imag = !NORMALIZE &&
        ((sum_imag_full > diff_max_q) || (sum_imag_full < diff_min_q));
    assign overflow_bottom_real = NORMALIZE ?
        ((bottom_real_scaled_normalized > product_max_q) ||
         (bottom_real_scaled_normalized < product_min_q)) :
        ((bottom_real_scaled_nonorm > product_max_q) ||
         (bottom_real_scaled_nonorm < product_min_q));
    assign overflow_bottom_imag = NORMALIZE ?
        ((bottom_imag_scaled_normalized > product_max_q) ||
         (bottom_imag_scaled_normalized < product_min_q)) :
        ((bottom_imag_scaled_nonorm > product_max_q) ||
         (bottom_imag_scaled_nonorm < product_min_q));

    wire [2:0] overflow_components_wire;
    assign overflow_components_wire =
        overflow_top_real + overflow_top_imag +
        overflow_bottom_real + overflow_bottom_imag;

    wire signed [FFT_WIDTH-1:0] butterfly_top_real;
    wire signed [FFT_WIDTH-1:0] butterfly_top_imag;
    wire signed [FFT_WIDTH-1:0] butterfly_bottom_real;
    wire signed [FFT_WIDTH-1:0] butterfly_bottom_imag;
    assign butterfly_top_real = NORMALIZE ?
        round_half_sum(sum_real_full) : saturate_diff(sum_real_full);
    assign butterfly_top_imag = NORMALIZE ?
        round_half_sum(sum_imag_full) : saturate_diff(sum_imag_full);
    assign butterfly_bottom_real = NORMALIZE ?
        saturate_product(bottom_real_scaled_normalized) :
        saturate_product(bottom_real_scaled_nonorm);
    assign butterfly_bottom_imag = NORMALIZE ?
        saturate_product(bottom_imag_scaled_normalized) :
        saturate_product(bottom_imag_scaled_nonorm);

    reg mem_we_a;
    reg mem_we_b;
    reg [5:0] mem_addr_a;
    reg [5:0] mem_addr_b;
    reg [FFT_WIDTH-1:0] mem_real_in_a;
    reg [FFT_WIDTH-1:0] mem_real_in_b;
    reg [FFT_WIDTH-1:0] mem_imag_in_a;
    reg [FFT_WIDTH-1:0] mem_imag_in_b;
    wire [FFT_WIDTH-1:0] mem_real_out_a;
    wire [FFT_WIDTH-1:0] mem_real_out_b;
    wire [FFT_WIDTH-1:0] mem_imag_out_a;
    wire [FFT_WIDTH-1:0] mem_imag_out_b;

    function [5:0] bit_reverse6;
        input [5:0] value;
        begin
            bit_reverse6 = {value[0], value[1], value[2],
                            value[3], value[4], value[5]};
        end
    endfunction

    wire signed [FFT_WIDTH-1:0] load_data_extended;
    assign load_data_extended =
        {{(FFT_WIDTH-INPUT_WIDTH){load_data[INPUT_WIDTH-1]}}, load_data};

    always @(*) begin
        mem_we_a = 1'b0;
        mem_we_b = 1'b0;
        mem_addr_a = 6'd0;
        mem_addr_b = 6'd0;
        mem_real_in_a = {FFT_WIDTH{1'b0}};
        mem_real_in_b = {FFT_WIDTH{1'b0}};
        mem_imag_in_a = {FFT_WIDTH{1'b0}};
        mem_imag_in_b = {FFT_WIDTH{1'b0}};
        if (!busy && load_en) begin
            mem_we_a = 1'b1;
            mem_addr_a = load_addr;
            mem_real_in_a = load_data_extended;
        end else begin
            case (state)
                S_READ, S_WAIT: begin
                    mem_addr_a = addr_a_calc;
                    mem_addr_b = addr_b_calc;
                end
                S_WRITE: begin
                    mem_we_a = 1'b1;
                    mem_we_b = 1'b1;
                    mem_addr_a = addr_a_saved;
                    mem_addr_b = addr_b_saved;
                    mem_real_in_a = butterfly_top_real;
                    mem_imag_in_a = butterfly_top_imag;
                    mem_real_in_b = butterfly_bottom_real;
                    mem_imag_in_b = butterfly_bottom_imag;
                end
                S_OUT_READ, S_OUT_WAIT, S_OUT_HOLD: begin
                    mem_addr_a = bit_reverse6(output_count);
                end
                default: begin
                    mem_addr_a = 6'd0;
                    mem_addr_b = 6'd0;
                end
            endcase
        end
    end

    dual_port_ram #(.DATA_WIDTH(FFT_WIDTH), .ADDR_WIDTH(6), .DEPTH(64),
                    .INIT_FILE("NONE")) real_memory (
        .clk(clk),
        .we_a(mem_we_a), .addr_a(mem_addr_a), .data_in_a(mem_real_in_a),
        .data_out_a(mem_real_out_a),
        .we_b(mem_we_b), .addr_b(mem_addr_b), .data_in_b(mem_real_in_b),
        .data_out_b(mem_real_out_b)
    );

    dual_port_ram #(.DATA_WIDTH(FFT_WIDTH), .ADDR_WIDTH(6), .DEPTH(64),
                    .INIT_FILE("NONE")) imag_memory (
        .clk(clk),
        .we_a(mem_we_a), .addr_a(mem_addr_a), .data_in_a(mem_imag_in_a),
        .data_out_a(mem_imag_out_a),
        .we_b(mem_we_b), .addr_b(mem_addr_b), .data_in_b(mem_imag_in_b),
        .data_out_b(mem_imag_out_b)
    );

    assign load_ready = !busy;

    always @(posedge clk) begin
        if (reset) begin
            state <= S_IDLE;
            stage_count <= 3'd0;
            butterfly_count <= 5'd0;
            output_count <= 6'd0;
            addr_a_saved <= 6'd0;
            addr_b_saved <= 6'd0;
            operand_a_real <= {FFT_WIDTH{1'b0}};
            operand_a_imag <= {FFT_WIDTH{1'b0}};
            operand_b_real <= {FFT_WIDTH{1'b0}};
            operand_b_imag <= {FFT_WIDTH{1'b0}};
            twiddle_real_saved <= {COEFF_WIDTH{1'b0}};
            twiddle_imag_saved <= {COEFF_WIDTH{1'b0}};
            busy <= 1'b0;
            done <= 1'b0;
            fft_valid <= 1'b0;
            fft_bin_out <= 6'd0;
            fft_real_out <= {FFT_WIDTH{1'b0}};
            fft_imag_out <= {FFT_WIDTH{1'b0}};
            overflow_event <= 1'b0;
            overflow_stage <= 3'd0;
            overflow_components <= 3'd0;
            overflow_total_components <= 32'd0;
            probe_event <= 1'b0;
            probe_stage <= 3'd0;
            probe_top_real <= {FFT_WIDTH{1'b0}};
            probe_top_imag <= {FFT_WIDTH{1'b0}};
            probe_bottom_real <= {FFT_WIDTH{1'b0}};
            probe_bottom_imag <= {FFT_WIDTH{1'b0}};
        end else begin
            done <= 1'b0;
            overflow_event <= 1'b0;
            overflow_components <= 3'd0;
            probe_event <= 1'b0;
            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    fft_valid <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        stage_count <= 3'd0;
                        butterfly_count <= 5'd0;
                        state <= S_READ;
                    end
                end
                S_READ: begin
                    addr_a_saved <= addr_a_calc;
                    addr_b_saved <= addr_b_calc;
                    twiddle_real_saved <= twiddle_real_wire;
                    twiddle_imag_saved <= twiddle_imag_wire;
                    state <= S_WAIT;
                end
                S_WAIT: begin
                    operand_a_real <= $signed(mem_real_out_a);
                    operand_a_imag <= $signed(mem_imag_out_a);
                    operand_b_real <= $signed(mem_real_out_b);
                    operand_b_imag <= $signed(mem_imag_out_b);
                    state <= S_WRITE;
                end
                S_WRITE: begin
                    probe_event <= 1'b1;
                    probe_stage <= stage_count;
                    probe_top_real <= butterfly_top_real;
                    probe_top_imag <= butterfly_top_imag;
                    probe_bottom_real <= butterfly_bottom_real;
                    probe_bottom_imag <= butterfly_bottom_imag;
                    if (overflow_components_wire != 0) begin
                        overflow_event <= 1'b1;
                        overflow_stage <= stage_count;
                        overflow_components <= overflow_components_wire;
                        overflow_total_components <=
                            overflow_total_components + overflow_components_wire;
                    end
                    if (butterfly_count == 5'd31) begin
                        butterfly_count <= 5'd0;
                        if (stage_count == 3'd5) begin
                            output_count <= 6'd0;
                            state <= S_OUT_READ;
                        end else begin
                            stage_count <= stage_count + 1'b1;
                            state <= S_READ;
                        end
                    end else begin
                        butterfly_count <= butterfly_count + 1'b1;
                        state <= S_READ;
                    end
                end
                S_OUT_READ: state <= S_OUT_WAIT;
                S_OUT_WAIT: begin
                    fft_bin_out <= output_count;
                    fft_real_out <= $signed(mem_real_out_a);
                    fft_imag_out <= $signed(mem_imag_out_a);
                    fft_valid <= 1'b1;
                    state <= S_OUT_HOLD;
                end
                S_OUT_HOLD: begin
                    if (fft_valid && fft_ready) begin
                        fft_valid <= 1'b0;
                        if (output_count == 6'd63)
                            state <= S_DONE;
                        else begin
                            output_count <= output_count + 1'b1;
                            state <= S_OUT_READ;
                        end
                    end
                end
                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                    busy <= 1'b0;
                end
            endcase
        end
    end
endmodule
