`timescale 1ns/1ps

module tb_lms_filter_time_serial;

    localparam integer DATA_WIDTH = 24;
    localparam signed [DATA_WIDTH-1:0] ONE_Q915 = 24'sd32768;
    localparam integer ADAPT_SAMPLES = 20000;
    localparam integer AVG_LENGTH = 256;

    reg clk;
    reg reset;
    reg signed [DATA_WIDTH-1:0] sample_in;
    reg sample_valid;
    wire sample_ready;
    reg adapt_enable;
    reg clear_coefficients;

    wire signed [DATA_WIDTH-1:0] error_sample;
    wire signed [DATA_WIDTH-1:0] prediction_sample;
    wire output_valid;
    reg output_ready;
    wire busy;
    wire error_saturated;
    wire estimate_saturated;
    wire coefficient_saturated;

    integer errors;
    integer n;
    integer wait_cycles;
    longint signed abs_error;
    longint unsigned first_error_sum;
    longint unsigned last_error_sum;
    longint unsigned first_error_average;
    longint unsigned last_error_average;
    reg signed [DATA_WIDTH-1:0] observed_error;
    reg signed [DATA_WIDTH-1:0] observed_prediction;

    lms_filter_time_serial #(
        .DATA_WIDTH      (24),
        .DATA_FRAC_BITS  (15),
        .COEFF_FRAC_BITS (20),
        .ACC_WIDTH       (52),
        .MU_SHIFT        (16)
    ) dut (
        .clk                    (clk),
        .reset                  (reset),
        .sample_in              (sample_in),
        .sample_valid           (sample_valid),
        .sample_ready           (sample_ready),
        .adapt_enable           (adapt_enable),
        .clear_coefficients     (clear_coefficients),
        .error_sample           (error_sample),
        .prediction_sample      (prediction_sample),
        .output_valid           (output_valid),
        .output_ready           (output_ready),
        .busy                   (busy),
        .error_saturated        (error_saturated),
        .estimate_saturated     (estimate_saturated),
        .coefficient_saturated  (coefficient_saturated)
    );

    initial clk = 1'b0;
    always #10 clk = ~clk;

    task automatic apply_reset;
        begin
            @(negedge clk);
            reset <= 1'b1;
            repeat (4) @(negedge clk);
            reset <= 1'b0;
            repeat (2) @(negedge clk);
        end
    endtask

    task automatic transact;
        input  reg signed [DATA_WIDTH-1:0] value;
        input  reg                         adaptation;
        output reg signed [DATA_WIDTH-1:0] captured_error;
        output reg signed [DATA_WIDTH-1:0] captured_prediction;
        begin
            wait_cycles = 0;
            while (!sample_ready) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100)
                    $fatal(1, "TIMEOUT esperando sample_ready.");
            end

            sample_in    <= value;
            adapt_enable <= adaptation;
            sample_valid <= 1'b1;
            @(negedge clk);
            sample_valid <= 1'b0;

            wait_cycles = 0;
            while (!output_valid) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
                if (wait_cycles > 100)
                    $fatal(1, "TIMEOUT esperando output_valid.");
            end

            captured_error      = error_sample;
            captured_prediction = prediction_sample;

            // Mantem a saida bloqueada por dois ciclos para verificar que os
            // dados permanecem estaveis durante backpressure.
            repeat (2) begin
                @(negedge clk);
                if (error_sample !== captured_error ||
                    prediction_sample !== captured_prediction ||
                    !output_valid) begin
                    errors = errors + 1;
                    $error("Saida mudou durante backpressure.");
                end
            end

            output_ready <= 1'b1;
            @(negedge clk);
            output_ready <= 1'b0;
        end
    endtask

    initial begin
        reset              = 1'b0;
        sample_in          = {DATA_WIDTH{1'b0}};
        sample_valid       = 1'b0;
        adapt_enable       = 1'b0;
        clear_coefficients = 1'b0;
        output_ready       = 1'b0;
        errors             = 0;
        first_error_sum    = 0;
        last_error_sum     = 0;

        apply_reset();

        // Com adaptacao desligada e coeficientes zerados:
        // prediction_sample=0 e error_sample=sample_in.
        transact(24'sd32768, 1'b0, observed_error, observed_prediction);
        if (observed_error !== 24'sd32768 ||
            observed_prediction !== 24'sd0) begin
            errors = errors + 1;
            $error("Bypass invalido para +1.0: e=%0d y=%0d",
                   observed_error, observed_prediction);
        end

        transact(-24'sd16384, 1'b0, observed_error, observed_prediction);
        if (observed_error !== -24'sd16384 ||
            observed_prediction !== 24'sd0) begin
            errors = errors + 1;
            $error("Bypass invalido para -0.5: e=%0d y=%0d",
                   observed_error, observed_prediction);
        end

        // Reinicia historico e coeficientes antes do teste de convergencia.
        @(negedge clk);
        clear_coefficients <= 1'b1;
        repeat (2) @(negedge clk);
        clear_coefficients <= 1'b0;
        repeat (2) @(negedge clk);

        // Para uma entrada constante, o erro medio deve diminuir conforme os
        // coeficientes aprendem a componente previsivel.
        for (n = 0; n < ADAPT_SAMPLES; n = n + 1) begin
            transact(ONE_Q915, 1'b1,
                     observed_error, observed_prediction);

            abs_error = $signed(observed_error);
            if (abs_error < 0)
                abs_error = -abs_error;

            if (n >= 8 && n < (8 + AVG_LENGTH))
                first_error_sum = first_error_sum + abs_error;

            if (n >= (ADAPT_SAMPLES - AVG_LENGTH))
                last_error_sum = last_error_sum + abs_error;

            if (error_saturated || estimate_saturated ||
                coefficient_saturated) begin
                errors = errors + 1;
                $error("Saturacao inesperada na amostra %0d.", n);
            end
        end

        first_error_average = first_error_sum / AVG_LENGTH;
        last_error_average  = last_error_sum  / AVG_LENGTH;

        $display("[LMS UNIT] erro medio inicial = %0d LSB", first_error_average);
        $display("[LMS UNIT] erro medio final   = %0d LSB", last_error_average);

        if (last_error_average >= first_error_average) begin
            errors = errors + 1;
            $error("O LMS nao apresentou convergencia.");
        end

        if (errors == 0)
            $display("[LMS UNIT] PASS");
        else
            $fatal(1, "[LMS UNIT] FAIL: erros=%0d", errors);

        $finish;
    end

endmodule
