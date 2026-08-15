`timescale 1ns/1ps

// Estagio FIR decimador sequencial para amostras Q9.15 ou Q11.16.
// Os coeficientes sao signed Q1.17; o produto e deslocado por
// COEFF_FRAC_BITS para preservar os bits fracionarios da amostra.
module fir_decimator_stage_dualmode #(
    parameter integer SAMPLE_WIDTH      = 24,
    parameter integer COEFF_WIDTH       = 18,
    parameter integer ACC_WIDTH         = 64,
    parameter integer COEFF_FRAC_BITS   = 17,
    parameter integer NUM_TAPS          = 47,
    parameter integer DECIMATION        = 4,
    parameter integer COEFF_ADDR_WIDTH  = 7,
    parameter INIT_FILE =
    "../coefficients/fir/stage1_decim4_q117.hex"
)(
    input  wire                            clk,
    input  wire                            reset,
    input  wire signed [SAMPLE_WIDTH-1:0]  sample_in,
    input  wire                            sample_valid,
    output wire                            sample_ready,
    output reg signed [SAMPLE_WIDTH-1:0]   sample_out,
    output reg                             sample_out_valid,
    input  wire                            sample_out_ready,
    output reg                             sample_out_saturated
);

    localparam integer TAP_ADDR_WIDTH =
        (NUM_TAPS <= 2) ? 1 : $clog2(NUM_TAPS);
    localparam integer VALID_COUNT_WIDTH =
        (NUM_TAPS <= 1) ? 1 : $clog2(NUM_TAPS + 1);
    localparam integer DECIM_COUNT_WIDTH =
        (DECIMATION <= 2) ? 1 : $clog2(DECIMATION);
    localparam integer PRODUCT_WIDTH = SAMPLE_WIDTH + COEFF_WIDTH;

    localparam [2:0] STATE_IDLE       = 3'd0;
    localparam [2:0] STATE_COEFF_REQ  = 3'd1;
    localparam [2:0] STATE_COEFF_WAIT = 3'd2;
    localparam [2:0] STATE_OUTPUT     = 3'd3;

    reg [2:0] state;
    reg signed [SAMPLE_WIDTH-1:0] sample_history [0:NUM_TAPS-1];
    reg [TAP_ADDR_WIDTH-1:0] write_pointer;
    reg [TAP_ADDR_WIDTH-1:0] newest_pointer;
    reg [TAP_ADDR_WIDTH-1:0] tap_index;
    reg [VALID_COUNT_WIDTH-1:0] valid_sample_count;
    reg [VALID_COUNT_WIDTH-1:0] active_valid_count;
    reg [DECIM_COUNT_WIDTH-1:0] decimation_counter;
    reg signed [ACC_WIDTH-1:0] accumulator;

    wire coefficient_read_enable;
    wire [COEFF_ADDR_WIDTH-1:0] coefficient_address;
    wire signed [COEFF_WIDTH-1:0] coefficient_value;
    wire coefficient_valid;
    wire coefficient_addr_error;

    reg signed [SAMPLE_WIDTH-1:0] delayed_sample;
    integer delayed_sample_index;

    wire signed [PRODUCT_WIDTH-1:0] product;
    wire signed [ACC_WIDTH-1:0] product_extended;
    wire signed [ACC_WIDTH-1:0] accumulator_plus_product;

    assign sample_ready = (state == STATE_IDLE);
    assign coefficient_read_enable = (state == STATE_COEFF_REQ);
    assign coefficient_address = tap_index;

    fir_coeff_rom_dualmode #(
        .COEFF_WIDTH (COEFF_WIDTH),
        .ADDR_WIDTH  (COEFF_ADDR_WIDTH),
        .NUM_TAPS    (NUM_TAPS),
        .INIT_FILE   (INIT_FILE)
    ) coefficient_rom (
        .clk          (clk),
        .reset        (reset),
        .read_enable  (coefficient_read_enable),
        .coeff_addr   (coefficient_address),
        .coeff_out    (coefficient_value),
        .coeff_valid  (coefficient_valid),
        .addr_error   (coefficient_addr_error)
    );

    always @(*) begin
        delayed_sample = {SAMPLE_WIDTH{1'b0}};
        delayed_sample_index = 0;

        if (tap_index < active_valid_count) begin
            if (newest_pointer >= tap_index)
                delayed_sample_index = newest_pointer - tap_index;
            else
                delayed_sample_index = newest_pointer + NUM_TAPS - tap_index;
            delayed_sample = sample_history[delayed_sample_index];
        end
    end

    assign product = $signed(delayed_sample) * $signed(coefficient_value);
    assign product_extended =
        {{(ACC_WIDTH-PRODUCT_WIDTH){product[PRODUCT_WIDTH-1]}}, product};
    assign accumulator_plus_product =
        $signed(accumulator) + $signed(product_extended);

    function automatic signed [SAMPLE_WIDTH-1:0] round_and_saturate;
        input signed [ACC_WIDTH-1:0] value;
        reg signed [ACC_WIDTH:0] wide_value;
        reg signed [ACC_WIDTH:0] magnitude;
        reg signed [ACC_WIDTH:0] rounded_value;
        reg signed [ACC_WIDTH:0] rounding_constant;
        reg signed [ACC_WIDTH:0] maximum_value;
        reg signed [ACC_WIDTH:0] minimum_value;
        begin
            wide_value = {value[ACC_WIDTH-1], value};
            rounding_constant =
                ({{ACC_WIDTH{1'b0}}, 1'b1} <<< (COEFF_FRAC_BITS - 1));
            maximum_value =
                ({{ACC_WIDTH{1'b0}}, 1'b1} <<< (SAMPLE_WIDTH - 1)) - 1;
            minimum_value =
                -({{ACC_WIDTH{1'b0}}, 1'b1} <<< (SAMPLE_WIDTH - 1));

            if (wide_value >= 0)
                rounded_value =
                    (wide_value + rounding_constant) >>> COEFF_FRAC_BITS;
            else begin
                magnitude = -wide_value;
                rounded_value =
                    -((magnitude + rounding_constant) >>> COEFF_FRAC_BITS);
            end

            if (rounded_value > maximum_value)
                round_and_saturate = {1'b0, {(SAMPLE_WIDTH-1){1'b1}}};
            else if (rounded_value < minimum_value)
                round_and_saturate = {1'b1, {(SAMPLE_WIDTH-1){1'b0}}};
            else
                round_and_saturate = rounded_value[SAMPLE_WIDTH-1:0];
        end
    endfunction

    function automatic rounding_saturates;
        input signed [ACC_WIDTH-1:0] value;
        reg signed [ACC_WIDTH:0] wide_value;
        reg signed [ACC_WIDTH:0] magnitude;
        reg signed [ACC_WIDTH:0] rounded_value;
        reg signed [ACC_WIDTH:0] rounding_constant;
        reg signed [ACC_WIDTH:0] maximum_value;
        reg signed [ACC_WIDTH:0] minimum_value;
        begin
            wide_value = {value[ACC_WIDTH-1], value};
            rounding_constant =
                ({{ACC_WIDTH{1'b0}}, 1'b1} <<< (COEFF_FRAC_BITS - 1));
            maximum_value =
                ({{ACC_WIDTH{1'b0}}, 1'b1} <<< (SAMPLE_WIDTH - 1)) - 1;
            minimum_value =
                -({{ACC_WIDTH{1'b0}}, 1'b1} <<< (SAMPLE_WIDTH - 1));

            if (wide_value >= 0)
                rounded_value =
                    (wide_value + rounding_constant) >>> COEFF_FRAC_BITS;
            else begin
                magnitude = -wide_value;
                rounded_value =
                    -((magnitude + rounding_constant) >>> COEFF_FRAC_BITS);
            end

            rounding_saturates =
                (rounded_value > maximum_value) ||
                (rounded_value < minimum_value);
        end
    endfunction

    always @(posedge clk) begin
        if (reset) begin
            state                <= STATE_IDLE;
            write_pointer        <= {TAP_ADDR_WIDTH{1'b0}};
            newest_pointer       <= {TAP_ADDR_WIDTH{1'b0}};
            tap_index            <= {TAP_ADDR_WIDTH{1'b0}};
            valid_sample_count   <= {VALID_COUNT_WIDTH{1'b0}};
            active_valid_count   <= {VALID_COUNT_WIDTH{1'b0}};
            decimation_counter   <= {DECIM_COUNT_WIDTH{1'b0}};
            accumulator          <= {ACC_WIDTH{1'b0}};
            sample_out           <= {SAMPLE_WIDTH{1'b0}};
            sample_out_valid     <= 1'b0;
            sample_out_saturated <= 1'b0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    sample_out_valid     <= 1'b0;
                    sample_out_saturated <= 1'b0;

                    if (sample_valid) begin
                        sample_history[write_pointer] <= sample_in;
                        newest_pointer <= write_pointer;

                        if (write_pointer == NUM_TAPS - 1)
                            write_pointer <= {TAP_ADDR_WIDTH{1'b0}};
                        else
                            write_pointer <= write_pointer + 1'b1;

                        if (valid_sample_count < NUM_TAPS) begin
                            valid_sample_count <= valid_sample_count + 1'b1;
                            active_valid_count <= valid_sample_count + 1'b1;
                        end
                        else begin
                            valid_sample_count <= valid_sample_count;
                            active_valid_count <= valid_sample_count;
                        end

                        if (decimation_counter == DECIMATION - 1) begin
                            decimation_counter <=
                                {DECIM_COUNT_WIDTH{1'b0}};
                            tap_index   <= {TAP_ADDR_WIDTH{1'b0}};
                            accumulator <= {ACC_WIDTH{1'b0}};
                            state       <= STATE_COEFF_REQ;
                        end
                        else
                            decimation_counter <= decimation_counter + 1'b1;
                    end
                end

                STATE_COEFF_REQ: state <= STATE_COEFF_WAIT;

                STATE_COEFF_WAIT: begin
                    if (coefficient_addr_error) begin
                        sample_out           <= {SAMPLE_WIDTH{1'b0}};
                        sample_out_valid     <= 1'b1;
                        sample_out_saturated <= 1'b0;
                        state                <= STATE_OUTPUT;
                    end
                    else if (coefficient_valid) begin
                        if (tap_index == NUM_TAPS - 1) begin
                            sample_out <=
                                round_and_saturate(accumulator_plus_product);
                            sample_out_saturated <=
                                rounding_saturates(accumulator_plus_product);
                            sample_out_valid <= 1'b1;
                            state <= STATE_OUTPUT;
                        end
                        else begin
                            accumulator <= accumulator_plus_product;
                            tap_index <= tap_index + 1'b1;
                            state <= STATE_COEFF_REQ;
                        end
                    end
                end

                STATE_OUTPUT: begin
                    if (sample_out_ready) begin
                        sample_out_valid     <= 1'b0;
                        sample_out_saturated <= 1'b0;
                        state                <= STATE_IDLE;
                    end
                end

                default: begin
                    state                <= STATE_IDLE;
                    sample_out_valid     <= 1'b0;
                    sample_out_saturated <= 1'b0;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (SAMPLE_WIDTH <= 1 || COEFF_WIDTH <= 1)
            $fatal(1, "[fir_decimator_stage_dualmode] Largura invalida.");
        if (ACC_WIDTH < PRODUCT_WIDTH + $clog2(NUM_TAPS) + 1)
            $fatal(1,
                "[fir_decimator_stage_dualmode] ACC_WIDTH=%0d insuficiente; recomendado >=%0d.",
                ACC_WIDTH, PRODUCT_WIDTH + $clog2(NUM_TAPS) + 1);
        if (COEFF_FRAC_BITS <= 0 || COEFF_FRAC_BITS >= COEFF_WIDTH)
            $fatal(1,
                "[fir_decimator_stage_dualmode] COEFF_FRAC_BITS invalido.");
        if (NUM_TAPS <= 0 || DECIMATION <= 1)
            $fatal(1,
                "[fir_decimator_stage_dualmode] NUM_TAPS/DECIMATION invalido.");
        if ((1 << COEFF_ADDR_WIDTH) < NUM_TAPS)
            $fatal(1,
                "[fir_decimator_stage_dualmode] COEFF_ADDR_WIDTH insuficiente.");
    end
`endif

endmodule
