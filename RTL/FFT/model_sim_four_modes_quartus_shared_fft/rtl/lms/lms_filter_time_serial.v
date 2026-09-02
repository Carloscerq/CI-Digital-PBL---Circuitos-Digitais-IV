`timescale 1ns/1ps

module lms_filter_time_serial #(
    parameter integer DATA_WIDTH       = 24,
    parameter integer DATA_FRAC_BITS   = 15,
    parameter integer COEFF_FRAC_BITS  = 20,
    parameter integer ACC_WIDTH        = 52,
    parameter integer MU_SHIFT         = 16
)(
    input  wire                           clk,
    input  wire                           reset,

    input  wire signed [DATA_WIDTH-1:0]  sample_in,
    input  wire                           sample_valid,
    output wire                           sample_ready,

    input  wire                           adapt_enable,
    input  wire                           clear_coefficients,

    output wire signed [DATA_WIDTH-1:0]  error_sample,
    output wire signed [DATA_WIDTH-1:0]  prediction_sample,
    output wire                           output_valid,
    input  wire                           output_ready,

    output wire                           busy,
    output wire                           error_saturated,
    output wire                           estimate_saturated,
    output wire                           coefficient_saturated
);

    localparam integer NUM_TAPS     = 8;
    localparam integer MULT_WIDTH   = 2 * DATA_WIDTH;
    localparam integer UPDATE_SHIFT =
        (2 * DATA_FRAC_BITS) + MU_SHIFT - COEFF_FRAC_BITS;

    localparam [1:0] STATE_IDLE   = 2'd0;
    localparam [1:0] STATE_MAC    = 2'd1;
    localparam [1:0] STATE_UPDATE = 2'd2;

    localparam signed [ACC_WIDTH-1:0] DATA_MAX_EXT =
        {{(ACC_WIDTH-DATA_WIDTH){1'b0}},
          1'b0, {(DATA_WIDTH-1){1'b1}}};

    localparam signed [ACC_WIDTH-1:0] DATA_MIN_EXT =
        {{(ACC_WIDTH-DATA_WIDTH){1'b1}},
          1'b1, {(DATA_WIDTH-1){1'b0}}};

    // DATA_WIDTH tambem e a largura dos coeficientes.
    localparam signed [ACC_WIDTH-1:0] COEFF_MAX_EXT = DATA_MAX_EXT;
    localparam signed [ACC_WIDTH-1:0] COEFF_MIN_EXT = DATA_MIN_EXT;

    reg [1:0] state;
    reg [2:0] tap_index;

    reg signed [DATA_WIDTH-1:0] sample_history [0:NUM_TAPS-1];
    reg signed [DATA_WIDTH-1:0] coefficients    [0:NUM_TAPS-1];

    reg signed [DATA_WIDTH-1:0] desired_register;
    reg signed [DATA_WIDTH-1:0] adaptation_error;
    reg                          adapt_enable_register;

    reg signed [ACC_WIDTH-1:0] mac_accumulator;

    reg signed [DATA_WIDTH-1:0] error_register;
    reg signed [DATA_WIDTH-1:0] estimate_register;
    reg                          output_valid_register;
    reg                          error_saturated_register;
    reg                          estimate_saturated_register;
    reg                          coefficient_saturated_register;

    integer i;

    wire input_transfer;
    wire output_transfer;

    assign sample_ready =
        (state == STATE_IDLE) && !output_valid_register &&
        !reset && !clear_coefficients;

    assign input_transfer  = sample_valid && sample_ready;
    assign output_transfer = output_valid_register && output_ready;

    assign error_sample          = error_register;
    assign prediction_sample     = estimate_register;
    assign output_valid          = output_valid_register;
    assign busy                  = (state != STATE_IDLE) || output_valid_register;
    assign error_saturated       = error_saturated_register;
    assign estimate_saturated    = estimate_saturated_register;
    assign coefficient_saturated = coefficient_saturated_register;

    // ------------------------------------------------------------------------
    // Um unico multiplicador fisico para as duas fases do algoritmo.
    // ------------------------------------------------------------------------
    wire signed [DATA_WIDTH-1:0] multiplier_operand_a;
    wire signed [DATA_WIDTH-1:0] multiplier_operand_b;
    wire signed [MULT_WIDTH-1:0] multiplier_result;

    assign multiplier_operand_a =
        (state == STATE_UPDATE)
            ? adaptation_error
            : coefficients[tap_index];

    assign multiplier_operand_b = sample_history[tap_index];

    assign multiplier_result =
        $signed(multiplier_operand_a) * $signed(multiplier_operand_b);

    // ------------------------------------------------------------------------
    // Produto escalar y(n) = sum(w_i*x_i).
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

    // Q9.15 * Q4.20 -> 35 bits fracionarios. Retirar os 20 bits
    // fracionarios do coeficiente devolve o resultado para Q9.15.
    assign estimate_scaled_comb =
        $signed(mac_sum_comb) >>> COEFF_FRAC_BITS;

    assign desired_extended =
        {{(ACC_WIDTH-DATA_WIDTH){desired_register[DATA_WIDTH-1]}},
          desired_register};

    assign error_full_comb =
        $signed(desired_extended) - $signed(estimate_scaled_comb);

    // ------------------------------------------------------------------------
    // Atualizacao w_i = w_i + mu*e*x_i.
    // ------------------------------------------------------------------------
    wire signed [MULT_WIDTH-1:0] coefficient_delta_raw;
    wire signed [ACC_WIDTH-1:0] coefficient_delta_extended;
    wire signed [ACC_WIDTH-1:0] coefficient_extended;
    wire signed [ACC_WIDTH-1:0] coefficient_sum_comb;

    assign coefficient_delta_raw =
        $signed(multiplier_result) >>> UPDATE_SHIFT;

    assign coefficient_delta_extended =
        {{(ACC_WIDTH-MULT_WIDTH){coefficient_delta_raw[MULT_WIDTH-1]}},
          coefficient_delta_raw};

    assign coefficient_extended =
        {{(ACC_WIDTH-DATA_WIDTH){coefficients[tap_index][DATA_WIDTH-1]}},
          coefficients[tap_index]};

    assign coefficient_sum_comb =
        $signed(coefficient_extended) +
        $signed(coefficient_delta_extended);

    // ------------------------------------------------------------------------
    // Saturacao explicita.
    // ------------------------------------------------------------------------
    function signed [DATA_WIDTH-1:0] saturate_data;
        input signed [ACC_WIDTH-1:0] value;
        begin
            if ($signed(value) > $signed(DATA_MAX_EXT))
                saturate_data = {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else if ($signed(value) < $signed(DATA_MIN_EXT))
                saturate_data = {1'b1, {(DATA_WIDTH-1){1'b0}}};
            else
                saturate_data = value[DATA_WIDTH-1:0];
        end
    endfunction

    function data_overflow;
        input signed [ACC_WIDTH-1:0] value;
        begin
            data_overflow =
                ($signed(value) > $signed(DATA_MAX_EXT)) ||
                ($signed(value) < $signed(DATA_MIN_EXT));
        end
    endfunction

    function signed [DATA_WIDTH-1:0] saturate_coefficient;
        input signed [ACC_WIDTH-1:0] value;
        begin
            if ($signed(value) > $signed(COEFF_MAX_EXT))
                saturate_coefficient =
                    {1'b0, {(DATA_WIDTH-1){1'b1}}};
            else if ($signed(value) < $signed(COEFF_MIN_EXT))
                saturate_coefficient =
                    {1'b1, {(DATA_WIDTH-1){1'b0}}};
            else
                saturate_coefficient = value[DATA_WIDTH-1:0];
        end
    endfunction

    function coefficient_overflow;
        input signed [ACC_WIDTH-1:0] value;
        begin
            coefficient_overflow =
                ($signed(value) > $signed(COEFF_MAX_EXT)) ||
                ($signed(value) < $signed(COEFF_MIN_EXT));
        end
    endfunction

    // ------------------------------------------------------------------------
    // Controle sequencial.
    // ------------------------------------------------------------------------
    always @(posedge clk) begin
        if (reset || clear_coefficients) begin
            state                              <= STATE_IDLE;
            tap_index                          <= 3'd0;
            desired_register                   <= {DATA_WIDTH{1'b0}};
            adaptation_error                   <= {DATA_WIDTH{1'b0}};
            adapt_enable_register              <= 1'b0;
            mac_accumulator                    <= {ACC_WIDTH{1'b0}};
            error_register                     <= {DATA_WIDTH{1'b0}};
            estimate_register                  <= {DATA_WIDTH{1'b0}};
            output_valid_register              <= 1'b0;
            error_saturated_register           <= 1'b0;
            estimate_saturated_register        <= 1'b0;
            coefficient_saturated_register     <= 1'b0;

            for (i = 0; i < NUM_TAPS; i = i + 1) begin
                sample_history[i] <= {DATA_WIDTH{1'b0}};
                coefficients[i]   <= {DATA_WIDTH{1'b0}};
            end
        end
        else begin
            if (output_transfer)
                output_valid_register <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (input_transfer) begin
                        // O historico ainda contem apenas d(n-1)..d(n-8).
                        desired_register              <= sample_in;
                        adapt_enable_register         <= adapt_enable;
                        mac_accumulator               <= {ACC_WIDTH{1'b0}};
                        tap_index                     <= 3'd0;
                        error_saturated_register      <= 1'b0;
                        estimate_saturated_register   <= 1'b0;
                        coefficient_saturated_register <= 1'b0;
                        state                         <= STATE_MAC;
                    end
                end

                STATE_MAC: begin
                    if (tap_index == 3'd7) begin
                        estimate_register <=
                            saturate_data(estimate_scaled_comb);

                        error_register <=
                            saturate_data(error_full_comb);

                        adaptation_error <=
                            saturate_data(error_full_comb);

                        estimate_saturated_register <=
                            data_overflow(estimate_scaled_comb);

                        error_saturated_register <=
                            data_overflow(error_full_comb);

                        tap_index <= 3'd0;

                        if (adapt_enable_register) begin
                            state <= STATE_UPDATE;
                        end
                        else begin
                            // Atualiza o historico somente depois da predicao.
                            for (i = NUM_TAPS-1; i > 0; i = i - 1)
                                sample_history[i] <= sample_history[i-1];
                            sample_history[0] <= desired_register;

                            output_valid_register <= 1'b1;
                            state                 <= STATE_IDLE;
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
                        // A amostra atual passa a ser historico para a proxima.
                        for (i = NUM_TAPS-1; i > 0; i = i - 1)
                            sample_history[i] <= sample_history[i-1];
                        sample_history[0] <= desired_register;

                        tap_index             <= 3'd0;
                        output_valid_register <= 1'b1;
                        state                 <= STATE_IDLE;
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

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != 24)
            $warning("[lms_filter_time_serial] O fluxo atual usa DATA_WIDTH=24.");

        if (ACC_WIDTH < (MULT_WIDTH + 3))
            $fatal(1,
                "[lms_filter_time_serial] ACC_WIDTH insuficiente para 8 taps.");

        if (UPDATE_SHIFT < 0)
            $fatal(1,
                "[lms_filter_time_serial] UPDATE_SHIFT nao pode ser negativo.");
    end
    // synthesis translate_on

endmodule
