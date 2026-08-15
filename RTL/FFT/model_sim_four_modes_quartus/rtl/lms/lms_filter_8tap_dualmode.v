`timescale 1ns/1ps

// ============================================================================
// lms_filter_8tap.v
//
// Filtro adaptativo LMS convencional, 8 taps, para cancelamento de ruido.
//
// d(n) : desired_sample   = sinal principal (sinal util + ruido)
// x(n) : reference_sample = referencia correlacionada com o ruido
// y(n) : noise_estimate   = estimativa do ruido
// e(n) : error_sample     = d(n) - y(n), saida filtrada
//
// Formatos selecionados pelo testbench:
//   Q9.15  : SAMPLE_WIDTH=24, SAMPLE_FRAC_BITS=15, COEFF_WIDTH=24
//   Q11.16 : SAMPLE_WIDTH=27, SAMPLE_FRAC_BITS=16, COEFF_WIDTH=27
// Os coeficientes mantem 20 bits fracionarios.
//   mu                                     : 2^(-MU_SHIFT)
//
// Arquitetura:
//   - um multiplicador compartilhado;
//   - 8 ciclos para o produto escalar;
//   - 8 ciclos para atualizar os coeficientes;
//   - protocolo valid/ready com backpressure;
//   - saturacao nas saidas Q9.15 e nos coeficientes.
//
// Com clock de 50 MHz e saida do decimador a 800 Hz, a implementacao serial
// possui ampla margem temporal e economiza DSPs em relacao a 8 multiplicadores
// paralelos.
// ============================================================================

module lms_filter_8tap_dualmode #(
    parameter integer SAMPLE_WIDTH      = 24,
    parameter integer SAMPLE_FRAC_BITS  = 15,
    parameter integer COEFF_WIDTH       = 24,
    parameter integer COEFF_FRAC_BITS   = 20,
    parameter integer ACC_WIDTH         = 48,
    parameter integer MU_SHIFT          = 10
)(
    input  wire                              clk,
    input  wire                              reset,

    input  wire signed [SAMPLE_WIDTH-1:0]    desired_sample,
    input  wire                              desired_valid,
    output wire                              desired_ready,

    input  wire signed [SAMPLE_WIDTH-1:0]    reference_sample,
    input  wire                              reference_valid,
    output wire                              reference_ready,

    input  wire                              adapt_enable,
    input  wire                              clear_coefficients,

    output wire signed [SAMPLE_WIDTH-1:0]    error_sample,
    output wire signed [SAMPLE_WIDTH-1:0]    noise_estimate,
    output wire                              error_valid,
    input  wire                              error_ready,

    output wire                              busy,
    output wire                              error_saturated,
    output wire                              estimate_saturated,
    output wire                              coefficient_saturated,

    // Saidas de depuracao. Todos os coeficientes usam Q4.20 por padrao.
    output wire signed [COEFF_WIDTH-1:0]      coeff0_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff1_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff2_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff3_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff4_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff5_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff6_out,
    output wire signed [COEFF_WIDTH-1:0]      coeff7_out
);

    localparam [1:0] STATE_IDLE   = 2'd0;
    localparam [1:0] STATE_MAC    = 2'd1;
    localparam [1:0] STATE_UPDATE = 2'd2;

    localparam integer MULT_WIDTH = COEFF_WIDTH + SAMPLE_WIDTH;
    localparam integer COEFF_SUM_WIDTH = MULT_WIDTH + 1;

    // Converte mu*e*x, cuja escala inicial e 2^(2*SAMPLE_FRAC_BITS),
    // para a escala dos coeficientes.
    localparam integer UPDATE_SHIFT =
        (2 * SAMPLE_FRAC_BITS) + MU_SHIFT - COEFF_FRAC_BITS;

    reg [1:0] state;
    reg [2:0] tap_index;

    reg signed [SAMPLE_WIDTH-1:0] sample_history [0:7];
    reg signed [COEFF_WIDTH-1:0]  coefficients [0:7];

    reg signed [SAMPLE_WIDTH-1:0] desired_register;
    reg signed [SAMPLE_WIDTH-1:0] adaptation_error;
    reg                            adapt_enable_register;

    reg signed [ACC_WIDTH-1:0] mac_accumulator;

    reg signed [SAMPLE_WIDTH-1:0] error_register;
    reg signed [SAMPLE_WIDTH-1:0] estimate_register;
    reg                            error_valid_register;
    reg                            error_saturated_register;
    reg                            estimate_saturated_register;
    reg                            coefficient_saturated_register;

    integer i;

    wire input_transfer;
    wire output_transfer;

    // Join sincronizado: nenhum dos dois fluxos e consumido sozinho.
    assign desired_ready =
        (state == STATE_IDLE) && !error_valid_register && reference_valid;

    assign reference_ready =
        (state == STATE_IDLE) && !error_valid_register && desired_valid;

    assign input_transfer =
        desired_valid && desired_ready && reference_valid && reference_ready;

    assign output_transfer = error_valid_register && error_ready;

    assign error_sample          = error_register;
    assign noise_estimate        = estimate_register;
    assign error_valid           = error_valid_register;
    assign busy                  = (state != STATE_IDLE) || error_valid_register;
    assign error_saturated       = error_saturated_register;
    assign estimate_saturated    = estimate_saturated_register;
    assign coefficient_saturated = coefficient_saturated_register;

    assign coeff0_out = coefficients[0];
    assign coeff1_out = coefficients[1];
    assign coeff2_out = coefficients[2];
    assign coeff3_out = coefficients[3];
    assign coeff4_out = coefficients[4];
    assign coeff5_out = coefficients[5];
    assign coeff6_out = coefficients[6];
    assign coeff7_out = coefficients[7];

    // ------------------------------------------------------------------------
    // Multiplicador compartilhado entre MAC e atualizacao dos coeficientes.
    // ------------------------------------------------------------------------
    wire signed [COEFF_WIDTH-1:0] multiplier_operand_a;
    wire signed [SAMPLE_WIDTH-1:0] multiplier_operand_b;
    wire signed [MULT_WIDTH-1:0] multiplier_result;

    assign multiplier_operand_a =
        (state == STATE_UPDATE)
            ? {{(COEFF_WIDTH-SAMPLE_WIDTH){adaptation_error[SAMPLE_WIDTH-1]}},
               adaptation_error}
            : coefficients[tap_index];

    assign multiplier_operand_b = sample_history[tap_index];

    assign multiplier_result =
        $signed(multiplier_operand_a) * $signed(multiplier_operand_b);

    // ------------------------------------------------------------------------
    // Caminho do produto escalar y(n) = sum(w_i*x_i).
    // ------------------------------------------------------------------------
    wire signed [ACC_WIDTH-1:0] multiplier_extended;
    wire signed [ACC_WIDTH-1:0] mac_sum_comb;
    wire signed [ACC_WIDTH-1:0] estimate_scaled_comb;
    wire signed [ACC_WIDTH-1:0] desired_extended;
    wire signed [ACC_WIDTH-1:0] error_full_comb;

    assign multiplier_extended =
        {{(ACC_WIDTH-MULT_WIDTH){multiplier_result[MULT_WIDTH-1]}},
         multiplier_result};

    assign mac_sum_comb =
        $signed(mac_accumulator) + $signed(multiplier_extended);

    // Produto Q9.15 x Q4.20 possui 35 bits fracionarios. A remocao dos
    // 20 bits do coeficiente retorna o resultado para 15 bits fracionarios.
    assign estimate_scaled_comb =
        $signed(mac_sum_comb) >>> COEFF_FRAC_BITS;

    assign desired_extended =
        {{(ACC_WIDTH-SAMPLE_WIDTH){desired_register[SAMPLE_WIDTH-1]}},
         desired_register};

    assign error_full_comb =
        $signed(desired_extended) - $signed(estimate_scaled_comb);

    // ------------------------------------------------------------------------
    // Caminho de atualizacao w_i <- w_i + mu*e*x_i.
    // ------------------------------------------------------------------------
    wire signed [MULT_WIDTH-1:0] coefficient_delta;
    wire signed [COEFF_SUM_WIDTH-1:0] coefficient_extended;
    wire signed [COEFF_SUM_WIDTH-1:0] delta_extended;
    wire signed [COEFF_SUM_WIDTH-1:0] coefficient_sum_comb;

    assign coefficient_delta =
        $signed(multiplier_result) >>> UPDATE_SHIFT;

    assign coefficient_extended =
        {{(COEFF_SUM_WIDTH-COEFF_WIDTH){coefficients[tap_index][COEFF_WIDTH-1]}},
         coefficients[tap_index]};

    assign delta_extended =
        {{(COEFF_SUM_WIDTH-MULT_WIDTH){coefficient_delta[MULT_WIDTH-1]}},
         coefficient_delta};

    assign coefficient_sum_comb =
        $signed(coefficient_extended) + $signed(delta_extended);

    // ------------------------------------------------------------------------
    // Saturacao.
    // ------------------------------------------------------------------------
    function signed [SAMPLE_WIDTH-1:0] saturate_sample;
        input signed [ACC_WIDTH-1:0] value;
        begin
            if (value > $signed({1'b0, {(SAMPLE_WIDTH-1){1'b1}}}))
                saturate_sample = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
            else if (value < $signed({1'b1, {(SAMPLE_WIDTH-1){1'b0}}}))
                saturate_sample = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
            else
                saturate_sample = value[SAMPLE_WIDTH-1:0];
        end
    endfunction

    function sample_overflow;
        input signed [ACC_WIDTH-1:0] value;
        begin
            sample_overflow =
                (value > $signed({1'b0, {(SAMPLE_WIDTH-1){1'b1}}})) ||
                (value < $signed({1'b1, {(SAMPLE_WIDTH-1){1'b0}}}));
        end
    endfunction

    function signed [COEFF_WIDTH-1:0] saturate_coefficient;
        input signed [COEFF_SUM_WIDTH-1:0] value;
        begin
            if (value > $signed({1'b0, {(COEFF_WIDTH-1){1'b1}}}))
                saturate_coefficient =
                    {1'b0, {(COEFF_WIDTH-1){1'b1}}};
            else if (value < $signed({1'b1, {(COEFF_WIDTH-1){1'b0}}}))
                saturate_coefficient =
                    {1'b1, {(COEFF_WIDTH-1){1'b0}}};
            else
                saturate_coefficient = value[COEFF_WIDTH-1:0];
        end
    endfunction

    function coefficient_overflow;
        input signed [COEFF_SUM_WIDTH-1:0] value;
        begin
            coefficient_overflow =
                (value > $signed({1'b0, {(COEFF_WIDTH-1){1'b1}}})) ||
                (value < $signed({1'b1, {(COEFF_WIDTH-1){1'b0}}}));
        end
    endfunction

    // ------------------------------------------------------------------------
    // Controle sequencial.
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || clear_coefficients) begin
            state                              <= STATE_IDLE;
            tap_index                          <= 3'd0;
            desired_register                   <= {SAMPLE_WIDTH{1'b0}};
            adaptation_error                   <= {SAMPLE_WIDTH{1'b0}};
            adapt_enable_register              <= 1'b0;
            mac_accumulator                    <= {ACC_WIDTH{1'b0}};
            error_register                     <= {SAMPLE_WIDTH{1'b0}};
            estimate_register                  <= {SAMPLE_WIDTH{1'b0}};
            error_valid_register               <= 1'b0;
            error_saturated_register           <= 1'b0;
            estimate_saturated_register        <= 1'b0;
            coefficient_saturated_register     <= 1'b0;

            for (i = 0; i < 8; i = i + 1) begin
                sample_history[i] <= {SAMPLE_WIDTH{1'b0}};
                coefficients[i]   <= {COEFF_WIDTH{1'b0}};
            end
        end
        else begin
            if (output_transfer)
                error_valid_register <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (input_transfer) begin
                        // x(n) entra no tap zero; as amostras anteriores
                        // deslocam-se para os taps seguintes.
                        for (i = 7; i > 0; i = i - 1)
                            sample_history[i] <= sample_history[i-1];

                        sample_history[0] <= reference_sample;
                        desired_register  <= desired_sample;
                        adapt_enable_register <= adapt_enable;

                        mac_accumulator                <= {ACC_WIDTH{1'b0}};
                        tap_index                       <= 3'd0;
                        error_saturated_register        <= 1'b0;
                        estimate_saturated_register     <= 1'b0;
                        coefficient_saturated_register  <= 1'b0;
                        state                           <= STATE_MAC;
                    end
                end

                STATE_MAC: begin
                    if (tap_index == 3'd7) begin
                        estimate_register <=
                            saturate_sample(estimate_scaled_comb);

                        error_register <=
                            saturate_sample(error_full_comb);

                        adaptation_error <=
                            saturate_sample(error_full_comb);

                        estimate_saturated_register <=
                            sample_overflow(estimate_scaled_comb);

                        error_saturated_register <=
                            sample_overflow(error_full_comb);

                        tap_index <= 3'd0;

                        if (adapt_enable_register) begin
                            state <= STATE_UPDATE;
                        end
                        else begin
                            error_valid_register <= 1'b1;
                            state                <= STATE_IDLE;
                        end
                    end
                    else begin
                        mac_accumulator <= mac_sum_comb;
                        tap_index       <= tap_index + 3'd1;
                    end
                end

                STATE_UPDATE: begin
                    coefficients[tap_index] <=
                        saturate_coefficient(coefficient_sum_comb);

                    if (coefficient_overflow(coefficient_sum_comb))
                        coefficient_saturated_register <= 1'b1;

                    if (tap_index == 3'd7) begin
                        tap_index            <= 3'd0;
                        error_valid_register <= 1'b1;
                        state                <= STATE_IDLE;
                    end
                    else begin
                        tap_index <= tap_index + 3'd1;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (COEFF_WIDTH < SAMPLE_WIDTH)
            $fatal(1, "[lms_filter_8tap] COEFF_WIDTH deve ser >= SAMPLE_WIDTH.");

        if (ACC_WIDTH < (MULT_WIDTH + 3))
            $fatal(1, "[lms_filter_8tap] ACC_WIDTH insuficiente para 8 produtos.");

        if (UPDATE_SHIFT < 0)
            $fatal(1, "[lms_filter_8tap] UPDATE_SHIFT nao pode ser negativo.");
    end
`endif

endmodule
