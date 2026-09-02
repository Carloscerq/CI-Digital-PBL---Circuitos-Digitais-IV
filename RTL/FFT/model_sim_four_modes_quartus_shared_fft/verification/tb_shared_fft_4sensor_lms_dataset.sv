`timescale 1ns/1ps

// Teste integrado Q9.15 com quatro LMS temporais e uma FFT compartilhada.
// Cada linha temporal dos quatro arquivos e entregue atomicamente ao DUT.
module tb_shared_fft_4sensor_lms_dataset #(
    parameter integer DATA_WIDTH           = 24,
    parameter integer FRAC_BITS            = 15,
    parameter integer NORMALIZE            = 1,
    parameter integer HOP_SIZE             = 64,
    parameter integer LMS_MU_SHIFT         = 16,
    parameter integer INPUT_SAMPLE_RATE_HZ = 25600
);

    localparam integer DECIMATION_FACTOR = 32;
    localparam integer FRAME_SIZE = 64;

    reg clk;
    reg reset;
    reg signed [DATA_WIDTH-1:0] sensor1_sample;
    reg signed [DATA_WIDTH-1:0] sensor2_sample;
    reg signed [DATA_WIDTH-1:0] sensor3_sample;
    reg signed [DATA_WIDTH-1:0] sensor4_sample;
    reg sample_valid;
    wire sample_ready;

    reg lms_adapt_enable;
    reg lms_clear_coefficients;

    wire fft_valid;
    reg fft_ready;
    wire [5:0] fft_bin;
    wire signed [DATA_WIDTH-1:0] fft_real;
    wire signed [DATA_WIDTH-1:0] fft_imag;
    wire [1:0] fft_sensor_id;
    wire fft_done;
    wire pipeline_busy;

    wire [3:0] decimated_events;
    wire [3:0] lms_output_events;
    wire [3:0] lms_error_saturation_events;
    wire [3:0] lms_prediction_saturation_events;
    wire [3:0] lms_coefficient_saturation_events;
    wire fft_overflow_event;
    wire [2:0] fft_overflow_stage;
    wire [2:0] fft_overflow_components;
    wire [1:0] fft_overflow_sensor_id;

    preprocess_fft_shared_4sensor_q915_lms #(
        .DATA_WIDTH   (DATA_WIDTH),
        .NORMALIZE    (NORMALIZE),
        .HOP_SIZE     (HOP_SIZE),
        .LMS_MU_SHIFT (LMS_MU_SHIFT)
    ) dut (
        .clk                                  (clk),
        .reset                                (reset),
        .sensor1_sample                       (sensor1_sample),
        .sensor2_sample                       (sensor2_sample),
        .sensor3_sample                       (sensor3_sample),
        .sensor4_sample                       (sensor4_sample),
        .sample_valid                         (sample_valid),
        .sample_ready                         (sample_ready),
        .lms_adapt_enable                     (lms_adapt_enable),
        .lms_clear_coefficients               (lms_clear_coefficients),
        .fft_valid                            (fft_valid),
        .fft_ready                            (fft_ready),
        .fft_bin                              (fft_bin),
        .fft_real                             (fft_real),
        .fft_imag                             (fft_imag),
        .fft_sensor_id                        (fft_sensor_id),
        .fft_done                             (fft_done),
        .pipeline_busy                        (pipeline_busy),
        .decimated_events                     (decimated_events),
        .lms_output_events                    (lms_output_events),
        .lms_error_saturation_events          (lms_error_saturation_events),
        .lms_prediction_saturation_events     (lms_prediction_saturation_events),
        .lms_coefficient_saturation_events    (lms_coefficient_saturation_events),
        .fir_stage1_saturation_events         (),
        .fir_stage2_saturation_events         (),
        .fir_stage3_saturation_events         (),
        .hann_saturation_event                (),
        .hann_saturation_sensor_id            (),
        .fft_overflow_event                   (fft_overflow_event),
        .fft_overflow_stage                   (fft_overflow_stage),
        .fft_overflow_components              (fft_overflow_components),
        .fft_overflow_sensor_id               (fft_overflow_sensor_id)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    string sensor1_file_name;
    string sensor2_file_name;
    string sensor3_file_name;
    string sensor4_file_name;
    string bins_file_name;
    string report_file_name;

    integer sensor1_fd;
    integer sensor2_fd;
    integer sensor3_fd;
    integer sensor4_fd;
    integer bins_fd;
    integer report_fd;
    integer scan1;
    integer scan2;
    integer scan3;
    integer scan4;
    integer max_frames;
    integer save_all_bins;
    integer adapt_enable_argument;
    integer output_limit;
    integer numeric_scale;
    integer raw_target;
    integer input_samples;
    integer expected_decimated_samples;
    integer expected_frames;
    integer drain_cycles;
    integer frame_count [0:3];
    integer received_bins [0:3];
    integer overflow_count [0:3];
    integer decimated_count [0:3];
    integer lms_output_count [0:3];
    integer lms_error_saturation_count [0:3];
    integer lms_prediction_saturation_count [0:3];
    integer lms_coefficient_saturation_count [0:3];
    integer i;
    integer output_sensor;

    reg [DATA_WIDTH-1:0] sensor1_word;
    reg [DATA_WIDTH-1:0] sensor2_word;
    reg [DATA_WIDTH-1:0] sensor3_word;
    reg [DATA_WIDTH-1:0] sensor4_word;

    task automatic send_sensor_quad;
        input signed [DATA_WIDTH-1:0] value1;
        input signed [DATA_WIDTH-1:0] value2;
        input signed [DATA_WIDTH-1:0] value3;
        input signed [DATA_WIDTH-1:0] value4;
        begin
            @(negedge clk);
            sensor1_sample = value1;
            sensor2_sample = value2;
            sensor3_sample = value3;
            sensor4_sample = value4;
            sample_valid = 1'b1;

            do @(posedge clk); while (!sample_ready);

            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 4; i = i + 1) begin
                frame_count[i]                       <= 0;
                received_bins[i]                     <= 0;
                overflow_count[i]                    <= 0;
                decimated_count[i]                   <= 0;
                lms_output_count[i]                  <= 0;
                lms_error_saturation_count[i]        <= 0;
                lms_prediction_saturation_count[i]   <= 0;
                lms_coefficient_saturation_count[i]  <= 0;
            end
        end
        else begin
            for (i = 0; i < 4; i = i + 1) begin
                if (decimated_events[i])
                    decimated_count[i] <= decimated_count[i] + 1;
                if (lms_output_events[i])
                    lms_output_count[i] <= lms_output_count[i] + 1;
                if (lms_error_saturation_events[i])
                    lms_error_saturation_count[i] <=
                        lms_error_saturation_count[i] + 1;
                if (lms_prediction_saturation_events[i])
                    lms_prediction_saturation_count[i] <=
                        lms_prediction_saturation_count[i] + 1;
                if (lms_coefficient_saturation_events[i])
                    lms_coefficient_saturation_count[i] <=
                        lms_coefficient_saturation_count[i] + 1;
            end

            if (fft_overflow_event)
                overflow_count[fft_overflow_sensor_id] <=
                    overflow_count[fft_overflow_sensor_id] +
                    fft_overflow_components;

            if (fft_valid && fft_ready) begin
                output_sensor = fft_sensor_id;

                if (fft_bin != received_bins[output_sensor])
                    $fatal(1,
                        "Sequencia de bins invalida: sensor=%0d bin=%0d esperado=%0d",
                        output_sensor + 1, fft_bin,
                        received_bins[output_sensor]);

                if (fft_bin < output_limit)
                    $fwrite(bins_fd,
                        "%0d,%0d,%0d,%0d,%0d,%.10f,%.10f\n",
                        output_sensor + 1,
                        frame_count[output_sensor], fft_bin,
                        $signed(fft_real), $signed(fft_imag),
                        $itor($signed(fft_real))/numeric_scale,
                        $itor($signed(fft_imag))/numeric_scale);

                if (fft_bin == 6'd63) begin
                    received_bins[output_sensor] <= 0;
                    frame_count[output_sensor] <=
                        frame_count[output_sensor] + 1;
                    $display(
                        "[SHARED_FFT_LMS] sensor=%0d frame=%0d concluido",
                        output_sensor + 1,
                        frame_count[output_sensor] + 1);
                end
                else begin
                    received_bins[output_sensor] <=
                        received_bins[output_sensor] + 1;
                end
            end
        end
    end

    initial begin
        reset = 1'b1;
        sensor1_sample = {DATA_WIDTH{1'b0}};
        sensor2_sample = {DATA_WIDTH{1'b0}};
        sensor3_sample = {DATA_WIDTH{1'b0}};
        sensor4_sample = {DATA_WIDTH{1'b0}};
        sample_valid = 1'b0;
        lms_adapt_enable = 1'b1;
        lms_clear_coefficients = 1'b0;
        fft_ready = 1'b1;
        input_samples = 0;
        max_frames = 1;
        save_all_bins = 0;
        adapt_enable_argument = 1;
        numeric_scale = 1 << FRAC_BITS;

        if (!$value$plusargs("SENSOR1_FILE=%s", sensor1_file_name) ||
            !$value$plusargs("SENSOR2_FILE=%s", sensor2_file_name) ||
            !$value$plusargs("SENSOR3_FILE=%s", sensor3_file_name) ||
            !$value$plusargs("SENSOR4_FILE=%s", sensor4_file_name) ||
            !$value$plusargs("OUTPUT_BINS_CSV=%s", bins_file_name) ||
            !$value$plusargs("OUTPUT_REPORT=%s", report_file_name))
            $fatal(1, "Plusargs de arquivos obrigatorios ausentes.");

        void'($value$plusargs("MAX_FRAMES=%d", max_frames));
        void'($value$plusargs("SAVE_ALL_BINS=%d", save_all_bins));
        void'($value$plusargs("ADAPT_ENABLE=%d", adapt_enable_argument));
        lms_adapt_enable = (adapt_enable_argument != 0);
        output_limit = save_all_bins ? 64 : 32;

        sensor1_fd = $fopen(sensor1_file_name, "r");
        sensor2_fd = $fopen(sensor2_file_name, "r");
        sensor3_fd = $fopen(sensor3_file_name, "r");
        sensor4_fd = $fopen(sensor4_file_name, "r");
        if (!sensor1_fd || !sensor2_fd || !sensor3_fd || !sensor4_fd)
            $fatal(1, "Nao foi possivel abrir os quatro arquivos de sensor.");

        bins_fd = $fopen(bins_file_name, "w");
        report_fd = $fopen(report_file_name, "w");
        if (!bins_fd || !report_fd)
            $fatal(1, "Nao foi possivel criar os arquivos de resultado.");

        $fwrite(bins_fd,
            "sensor,frame_index,bin,real_q,imag_q,real_value,imag_value\n");

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        if (max_frames > 0)
            raw_target = DECIMATION_FACTOR *
                (FRAME_SIZE + ((max_frames - 1) * HOP_SIZE));
        else
            raw_target = 0;

        while ((raw_target == 0) || (input_samples < raw_target)) begin
            scan1 = $fscanf(sensor1_fd, "%h", sensor1_word);
            scan2 = $fscanf(sensor2_fd, "%h", sensor2_word);
            scan3 = $fscanf(sensor3_fd, "%h", sensor3_word);
            scan4 = $fscanf(sensor4_fd, "%h", sensor4_word);
            if (scan1 != 1 || scan2 != 1 || scan3 != 1 || scan4 != 1)
                break;

            send_sensor_quad(
                $signed(sensor1_word), $signed(sensor2_word),
                $signed(sensor3_word), $signed(sensor4_word));
            input_samples = input_samples + 1;
        end

        expected_decimated_samples = input_samples / DECIMATION_FACTOR;
        if (expected_decimated_samples >= FRAME_SIZE)
            expected_frames = 1 +
                ((expected_decimated_samples - FRAME_SIZE) / HOP_SIZE);
        else
            expected_frames = 0;
        if (max_frames > 0 && expected_frames > max_frames)
            expected_frames = max_frames;

        drain_cycles = 0;
        while ((frame_count[0] < expected_frames ||
                frame_count[1] < expected_frames ||
                frame_count[2] < expected_frames ||
                frame_count[3] < expected_frames) &&
               drain_cycles < 50000000) begin
            @(posedge clk);
            drain_cycles = drain_cycles + 1;
        end

        if (frame_count[0] != expected_frames ||
            frame_count[1] != expected_frames ||
            frame_count[2] != expected_frames ||
            frame_count[3] != expected_frames)
            $fatal(1,
                "Timeout: frames=%0d,%0d,%0d,%0d esperados=%0d",
                frame_count[0], frame_count[1], frame_count[2],
                frame_count[3], expected_frames);

        repeat (3) @(posedge clk);

        for (i = 0; i < 4; i = i + 1) begin
            if (decimated_count[i] != expected_decimated_samples)
                $fatal(1,
                    "Contagem do decimador invalida: sensor=%0d obtido=%0d esperado=%0d",
                    i + 1, decimated_count[i], expected_decimated_samples);
            if (lms_output_count[i] != expected_decimated_samples)
                $fatal(1,
                    "Contagem do LMS invalida: sensor=%0d obtido=%0d esperado=%0d",
                    i + 1, lms_output_count[i], expected_decimated_samples);
        end

        $fwrite(report_fd, "data_width=%0d\n", DATA_WIDTH);
        $fwrite(report_fd, "fractional_bits=%0d\n", FRAC_BITS);
        $fwrite(report_fd, "normalize=%0d\n", NORMALIZE);
        $fwrite(report_fd, "hop_size=%0d\n", HOP_SIZE);
        $fwrite(report_fd, "lms_adapt_enable=%0d\n", lms_adapt_enable);
        $fwrite(report_fd, "lms_mu_shift=%0d\n", LMS_MU_SHIFT);
        $fwrite(report_fd, "input_samples=%0d\n", input_samples);
        $fwrite(report_fd, "expected_decimated_samples=%0d\n",
                expected_decimated_samples);

        for (i = 0; i < 4; i = i + 1) begin
            $fwrite(report_fd, "decimated_sensor%0d=%0d\n",
                    i + 1, decimated_count[i]);
            $fwrite(report_fd, "lms_outputs_sensor%0d=%0d\n",
                    i + 1, lms_output_count[i]);
            $fwrite(report_fd, "frames_sensor%0d=%0d\n",
                    i + 1, frame_count[i]);
            $fwrite(report_fd, "lms_error_saturation_sensor%0d=%0d\n",
                    i + 1, lms_error_saturation_count[i]);
            $fwrite(report_fd, "lms_prediction_saturation_sensor%0d=%0d\n",
                    i + 1, lms_prediction_saturation_count[i]);
            $fwrite(report_fd, "lms_coefficient_saturation_sensor%0d=%0d\n",
                    i + 1, lms_coefficient_saturation_count[i]);
            $fwrite(report_fd, "fft_overflow_sensor%0d=%0d\n",
                    i + 1, overflow_count[i]);
        end
        $fwrite(report_fd, "status=PASS\n");

        $display(
            "[SHARED_FFT_LMS] PASS: entradas=%0d decimadas=%0d frames_por_sensor=%0d",
            input_samples, expected_decimated_samples, expected_frames);

        $fclose(sensor1_fd);
        $fclose(sensor2_fd);
        $fclose(sensor3_fd);
        $fclose(sensor4_fd);
        $fclose(bins_fd);
        $fclose(report_fd);
        $finish;
    end

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != 24 || FRAC_BITS != 15)
            $fatal(1, "Este teste integrado espera o modo Q9.15.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1, "HOP_SIZE deve estar entre 1 e 64.");
        if (LMS_MU_SHIFT < 1)
            $fatal(1, "LMS_MU_SHIFT invalido.");
    end
    // synthesis translate_on

endmodule
