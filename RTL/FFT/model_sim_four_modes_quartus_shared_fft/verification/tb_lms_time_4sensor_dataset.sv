`timescale 1ns/1ps

module tb_lms_time_4sensor_dataset;

    localparam integer DATA_WIDTH = 24;

    reg clk;
    reg reset;
    reg clear_coefficients;
    reg adapt_enable;

    reg  signed [DATA_WIDTH-1:0] sample_in [0:3];
    reg  [3:0] sample_valid;
    wire [3:0] sample_ready;
    wire signed [DATA_WIDTH-1:0] error_sample [0:3];
    wire signed [DATA_WIDTH-1:0] prediction_sample [0:3];
    wire [3:0] output_valid;
    reg  [3:0] output_ready;
    wire [3:0] busy;
    wire [3:0] error_saturated;
    wire [3:0] estimate_saturated;
    wire [3:0] coefficient_saturated;

    string sensor_file [0:3];
    string output_csv_name;
    string report_file_name;

    integer sensor_fd [0:3];
    integer output_fd;
    integer report_fd;
    integer read_status [0:3];
    integer saturation_error_count [0:3];
    integer saturation_estimate_count [0:3];
    integer saturation_coefficient_count [0:3];
    integer input_count;
    integer output_count [0:3];
    integer max_samples;
    integer save_samples;
    integer wait_cycles;
    integer s;
    integer finished;
    reg [DATA_WIDTH-1:0] input_word [0:3];

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : GEN_LMS
            lms_filter_time_serial #(
                .DATA_WIDTH      (24),
                .DATA_FRAC_BITS  (15),
                .COEFF_FRAC_BITS (20),
                .ACC_WIDTH       (52),
                .MU_SHIFT        (16)
            ) dut (
                .clk                    (clk),
                .reset                  (reset),
                .sample_in              (sample_in[g]),
                .sample_valid           (sample_valid[g]),
                .sample_ready           (sample_ready[g]),
                .adapt_enable           (adapt_enable),
                .clear_coefficients     (clear_coefficients),
                .error_sample           (error_sample[g]),
                .prediction_sample      (prediction_sample[g]),
                .output_valid           (output_valid[g]),
                .output_ready           (output_ready[g]),
                .busy                   (busy[g]),
                .error_saturated        (error_saturated[g]),
                .estimate_saturated     (estimate_saturated[g]),
                .coefficient_saturated  (coefficient_saturated[g])
            );
        end
    endgenerate

    initial clk = 1'b0;
    always #10 clk = ~clk;

    initial begin
        reset              = 1'b1;
        clear_coefficients = 1'b0;
        adapt_enable       = 1'b1;
        sample_valid       = 4'b0000;
        output_ready       = 4'b0000;
        input_count        = 0;
        finished           = 0;

        for (s = 0; s < 4; s = s + 1) begin
            sample_in[s]                       = '0;
            output_count[s]                    = 0;
            saturation_error_count[s]          = 0;
            saturation_estimate_count[s]       = 0;
            saturation_coefficient_count[s]    = 0;
        end

        if (!$value$plusargs("SENSOR1_FILE=%s", sensor_file[0]))
            $fatal(1, "Plusarg SENSOR1_FILE ausente.");
        if (!$value$plusargs("SENSOR2_FILE=%s", sensor_file[1]))
            $fatal(1, "Plusarg SENSOR2_FILE ausente.");
        if (!$value$plusargs("SENSOR3_FILE=%s", sensor_file[2]))
            $fatal(1, "Plusarg SENSOR3_FILE ausente.");
        if (!$value$plusargs("SENSOR4_FILE=%s", sensor_file[3]))
            $fatal(1, "Plusarg SENSOR4_FILE ausente.");
        if (!$value$plusargs("OUTPUT_CSV=%s", output_csv_name))
            output_csv_name = "lms_4sensor_outputs.csv";
        if (!$value$plusargs("REPORT_FILE=%s", report_file_name))
            report_file_name = "lms_4sensor_report.txt";
        if (!$value$plusargs("MAX_SAMPLES=%d", max_samples))
            max_samples = 0;
        if (!$value$plusargs("SAVE_SAMPLES=%d", save_samples))
            save_samples = 1024;

        for (s = 0; s < 4; s = s + 1) begin
            sensor_fd[s] = $fopen(sensor_file[s], "r");
            if (sensor_fd[s] == 0)
                $fatal(1, "Nao foi possivel abrir %s", sensor_file[s]);
        end

        output_fd = $fopen(output_csv_name, "w");
        if (output_fd == 0)
            $fatal(1, "Nao foi possivel criar %s", output_csv_name);

        $fwrite(output_fd,
        "sample_index,sensor,input_q915,error_q915,prediction_q915,error_saturated,prediction_saturated,coefficient_saturated\n");

        repeat (5) @(negedge clk);
        reset = 1'b0;
        repeat (2) @(negedge clk);

        while (!finished && ((max_samples == 0) ||
                             (input_count < max_samples))) begin
            for (s = 0; s < 4; s = s + 1)
                read_status[s] = $fscanf(sensor_fd[s], "%h", input_word[s]);

            if ((read_status[0] == 1) && (read_status[1] == 1) &&
                (read_status[2] == 1) && (read_status[3] == 1)) begin

                wait_cycles = 0;
                while (sample_ready !== 4'b1111) begin
                    @(negedge clk);
                    wait_cycles = wait_cycles + 1;
                    if (wait_cycles > 100)
                        $fatal(1, "TIMEOUT esperando sample_ready.");
                end

                for (s = 0; s < 4; s = s + 1)
                    sample_in[s] = input_word[s];

                sample_valid = 4'b1111;
                @(negedge clk);
                sample_valid = 4'b0000;

                wait_cycles = 0;
                while (output_valid !== 4'b1111) begin
                    @(negedge clk);
                    wait_cycles = wait_cycles + 1;
                    if (wait_cycles > 100)
                        $fatal(1, "TIMEOUT esperando output_valid.");
                end

                for (s = 0; s < 4; s = s + 1) begin
                    output_count[s] = output_count[s] + 1;
                    if (error_saturated[s])
                        saturation_error_count[s] =
                            saturation_error_count[s] + 1;
                    if (estimate_saturated[s])
                        saturation_estimate_count[s] =
                            saturation_estimate_count[s] + 1;
                    if (coefficient_saturated[s])
                        saturation_coefficient_count[s] =
                            saturation_coefficient_count[s] + 1;

                    if ((save_samples < 0) ||
                        (input_count < save_samples)) begin
                        $fwrite(output_fd,
                            "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                            input_count, s + 1,
                            $signed(input_word[s]),
                            $signed(error_sample[s]),
                            $signed(prediction_sample[s]),
                            error_saturated[s],
                            estimate_saturated[s],
                            coefficient_saturated[s]);
                    end
                end

                input_count = input_count + 1;

                if ((input_count % 100000) == 0)
                    $display("[LMS DATASET] entradas=%0d", input_count);

                output_ready = 4'b1111;
                @(negedge clk);
                output_ready = 4'b0000;
            end
            else if ((read_status[0] != 1) && (read_status[1] != 1) &&
                     (read_status[2] != 1) && (read_status[3] != 1)) begin
                finished = 1;
            end
            else begin
                $fatal(1,
                    "Os quatro arquivos nao possuem a mesma quantidade de amostras.");
            end
        end

        for (s = 0; s < 4; s = s + 1)
            $fclose(sensor_fd[s]);
        $fclose(output_fd);

        report_fd = $fopen(report_file_name, "w");
        if (report_fd == 0)
            $fatal(1, "Nao foi possivel criar %s", report_file_name);

        $fwrite(report_fd, "input_samples=%0d\n", input_count);
        $fwrite(report_fd, "mu_shift=16\n");
        $fwrite(report_fd, "mu=1/65536\n");
        for (s = 0; s < 4; s = s + 1) begin
            $fwrite(report_fd, "outputs_sensor%0d=%0d\n",
                    s + 1, output_count[s]);
            $fwrite(report_fd, "error_saturation_sensor%0d=%0d\n",
                    s + 1, saturation_error_count[s]);
            $fwrite(report_fd, "prediction_saturation_sensor%0d=%0d\n",
                    s + 1, saturation_estimate_count[s]);
            $fwrite(report_fd, "coefficient_saturation_sensor%0d=%0d\n",
                    s + 1, saturation_coefficient_count[s]);
        end
        $fwrite(report_fd, "status=PASS\n");
        $fclose(report_fd);

        $display("[LMS DATASET] PASS: entradas=%0d saidas_por_sensor=%0d",
                 input_count, output_count[0]);
        $finish;
    end

endmodule
