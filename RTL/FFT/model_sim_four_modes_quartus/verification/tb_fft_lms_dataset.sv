`timescale 1ns/1ps

// Testbench dos quatro modos 
// FIR/32 -> LMS opcional -> frame64/hop -> media -> Hann -> FFT64.
module tb_fft_lms_dataset #(
    parameter integer DATA_WIDTH            = 24,
    parameter integer FRAC_BITS             = 15,
    parameter integer NORMALIZE             = 1,
    parameter integer USE_LMS               = 0,
    parameter integer MU_SHIFT              = 16,
    parameter integer HOP_SIZE              = 8,
    parameter integer INPUT_SAMPLE_RATE_HZ  = 25600
);

    localparam integer DECIMATION_FACTOR = 32;
    localparam integer FRAME_SIZE = 64;

    reg clk;
    reg reset;
    reg signed [DATA_WIDTH-1:0] desired_sample;
    reg desired_valid;
    wire desired_ready;
    reg signed [DATA_WIDTH-1:0] reference_sample;
    reg reference_valid;
    wire reference_ready;
    reg adapt_enable;
    reg clear_coefficients;

    wire fft_valid;
    reg fft_ready;
    wire [5:0] fft_bin;
    wire signed [DATA_WIDTH-1:0] fft_real;
    wire signed [DATA_WIDTH-1:0] fft_imag;
    wire fft_done;
    wire pipeline_busy;

    wire desired_decimated_event;
    wire reference_decimated_event;
    wire lms_input_event;
    wire lms_output_event;
    wire desired_fir_stage1_saturation_event;
    wire desired_fir_stage2_saturation_event;
    wire desired_fir_stage3_saturation_event;
    wire reference_fir_stage1_saturation_event;
    wire reference_fir_stage2_saturation_event;
    wire reference_fir_stage3_saturation_event;
    wire lms_error_saturated;
    wire lms_estimate_saturated;
    wire lms_coefficient_saturated;
    wire hann_saturation_event;
    wire fft_overflow_event;
    wire [2:0] fft_overflow_stage;
    wire [2:0] fft_overflow_components;

    preprocess_lms_fft_four_modes #(
        .DATA_WIDTH  (DATA_WIDTH),
        .FRAC_BITS   (FRAC_BITS),
        .NORMALIZE   (NORMALIZE),
        .USE_LMS     (USE_LMS),
        .MU_SHIFT    (MU_SHIFT),
        .HOP_SIZE    (HOP_SIZE)
    ) dut (
        .clk                                      (clk),
        .reset                                    (reset),
        .desired_sample                           (desired_sample),
        .desired_valid                            (desired_valid),
        .desired_ready                            (desired_ready),
        .reference_sample                         (reference_sample),
        .reference_valid                          (reference_valid),
        .reference_ready                          (reference_ready),
        .adapt_enable                             (adapt_enable),
        .clear_coefficients                       (clear_coefficients),
        .fft_valid                                (fft_valid),
        .fft_ready                                (fft_ready),
        .fft_bin                                  (fft_bin),
        .fft_real                                 (fft_real),
        .fft_imag                                 (fft_imag),
        .fft_done                                 (fft_done),
        .pipeline_busy                            (pipeline_busy),
        .desired_decimated_event                  (desired_decimated_event),
        .reference_decimated_event                (reference_decimated_event),
        .lms_input_event                          (lms_input_event),
        .lms_output_event                         (lms_output_event),
        .desired_fir_stage1_saturation_event      (desired_fir_stage1_saturation_event),
        .desired_fir_stage2_saturation_event      (desired_fir_stage2_saturation_event),
        .desired_fir_stage3_saturation_event      (desired_fir_stage3_saturation_event),
        .reference_fir_stage1_saturation_event    (reference_fir_stage1_saturation_event),
        .reference_fir_stage2_saturation_event    (reference_fir_stage2_saturation_event),
        .reference_fir_stage3_saturation_event    (reference_fir_stage3_saturation_event),
        .lms_error_saturated                      (lms_error_saturated),
        .lms_estimate_saturated                   (lms_estimate_saturated),
        .lms_coefficient_saturated                (lms_coefficient_saturated),
        .hann_saturation_event                    (hann_saturation_event),
        .fft_overflow_event                       (fft_overflow_event),
        .fft_overflow_stage                       (fft_overflow_stage),
        .fft_overflow_components                  (fft_overflow_components)
    );

    initial begin
        clk = 1'b0;
        forever #10 clk = ~clk;
    end

    reg [8*1024-1:0] desired_file_name;
    reg [8*1024-1:0] reference_file_name;
    reg [8*1024-1:0] bins_file_name;
    reg [8*1024-1:0] frames_file_name;
    reg [8*1024-1:0] report_file_name;
    reg [8*128-1:0] mode_name;

    integer desired_fd;
    integer reference_fd;
    integer bins_fd;
    integer frames_fd;
    integer report_fd;
    integer scan_desired;
    integer scan_reference;
    integer max_frames;
    integer adapt_samples;
    integer save_all_bins;
    integer progress_frames;
    integer output_limit;
    integer numeric_scale;
    integer fft_scale_divisor;
    integer raw_target;
    integer expected_decimated_samples;
    integer expected_frames;
    integer drain_cycles;

    integer input_samples;
    integer desired_decimated_samples;
    integer reference_decimated_samples;
    integer lms_input_samples;
    integer frame_count;
    integer received_bins;
    integer saved_bin_count;

    integer desired_fir_stage1_saturations;
    integer desired_fir_stage2_saturations;
    integer desired_fir_stage3_saturations;
    integer reference_fir_stage1_saturations;
    integer reference_fir_stage2_saturations;
    integer reference_fir_stage3_saturations;
    integer lms_error_saturations;
    integer lms_estimate_saturations;
    integer lms_coefficient_saturations;
    integer hann_saturations;
    integer fft_overflow_total;
    integer fft_overflow_by_stage [0:5];
    integer fft_overflow_frame;
    integer fft_overflow_stage_frame [0:5];

    reg signed [DATA_WIDTH-1:0] frame_min_q;
    reg signed [DATA_WIDTH-1:0] frame_max_q;
    reg [DATA_WIDTH-1:0] desired_word;
    reg [DATA_WIDTH-1:0] reference_word;
    reg run_pass;

    integer i;

    always @(*) begin
        adapt_enable =
            (adapt_samples <= 0) || (lms_input_samples < adapt_samples);
    end

    task automatic send_input_pair;
        input signed [DATA_WIDTH-1:0] d_value;
        input signed [DATA_WIDTH-1:0] x_value;
        begin
            @(negedge clk);
            desired_sample = d_value;
            desired_valid = 1'b1;
            reference_sample = x_value;
            reference_valid = (USE_LMS != 0);

            if (USE_LMS != 0) begin
                do @(posedge clk);
                while (!(desired_ready && reference_ready));
            end
            else begin
                do @(posedge clk); while (!desired_ready);
            end

            @(negedge clk);
            desired_valid = 1'b0;
            reference_valid = 1'b0;
        end
    endtask

    // Contadores da cadeia temporal.
    always @(posedge clk) begin
        if (reset) begin
            desired_decimated_samples <= 0;
            reference_decimated_samples <= 0;
            lms_input_samples <= 0;
            desired_fir_stage1_saturations <= 0;
            desired_fir_stage2_saturations <= 0;
            desired_fir_stage3_saturations <= 0;
            reference_fir_stage1_saturations <= 0;
            reference_fir_stage2_saturations <= 0;
            reference_fir_stage3_saturations <= 0;
            lms_error_saturations <= 0;
            lms_estimate_saturations <= 0;
            lms_coefficient_saturations <= 0;
            hann_saturations <= 0;
        end
        else begin
            if (desired_decimated_event)
                desired_decimated_samples <= desired_decimated_samples + 1;
            if (reference_decimated_event)
                reference_decimated_samples <=
                    reference_decimated_samples + 1;
            if (lms_input_event)
                lms_input_samples <= lms_input_samples + 1;

            if (desired_fir_stage1_saturation_event)
                desired_fir_stage1_saturations <=
                    desired_fir_stage1_saturations + 1;
            if (desired_fir_stage2_saturation_event)
                desired_fir_stage2_saturations <=
                    desired_fir_stage2_saturations + 1;
            if (desired_fir_stage3_saturation_event)
                desired_fir_stage3_saturations <=
                    desired_fir_stage3_saturations + 1;
            if (reference_fir_stage1_saturation_event)
                reference_fir_stage1_saturations <=
                    reference_fir_stage1_saturations + 1;
            if (reference_fir_stage2_saturation_event)
                reference_fir_stage2_saturations <=
                    reference_fir_stage2_saturations + 1;
            if (reference_fir_stage3_saturation_event)
                reference_fir_stage3_saturations <=
                    reference_fir_stage3_saturations + 1;

            if (lms_output_event) begin
                if (lms_error_saturated)
                    lms_error_saturations <= lms_error_saturations + 1;
                if (lms_estimate_saturated)
                    lms_estimate_saturations <=
                        lms_estimate_saturations + 1;
                if (lms_coefficient_saturated)
                    lms_coefficient_saturations <=
                        lms_coefficient_saturations + 1;
            end

            if (hann_saturation_event)
                hann_saturations <= hann_saturations + 1;
        end
    end

    // Saida FFT, auditoria por frame e gravacao dos CSVs.
    always @(posedge clk) begin
        if (reset) begin
            frame_count <= 0;
            received_bins <= 0;
            saved_bin_count <= 0;
            frame_min_q <= {1'b0, {(DATA_WIDTH-1){1'b1}}};
            frame_max_q <= {1'b1, {(DATA_WIDTH-1){1'b0}}};
            fft_overflow_total <= 0;
            fft_overflow_frame <= 0;
            for (i = 0; i < 6; i = i + 1) begin
                fft_overflow_by_stage[i] <= 0;
                fft_overflow_stage_frame[i] <= 0;
            end
        end
        else begin
            if (fft_overflow_event) begin
                fft_overflow_total <=
                    fft_overflow_total + fft_overflow_components;
                fft_overflow_frame <=
                    fft_overflow_frame + fft_overflow_components;
                fft_overflow_by_stage[fft_overflow_stage] <=
                    fft_overflow_by_stage[fft_overflow_stage] +
                    fft_overflow_components;
                fft_overflow_stage_frame[fft_overflow_stage] <=
                    fft_overflow_stage_frame[fft_overflow_stage] +
                    fft_overflow_components;
            end

            if (fft_valid && fft_ready) begin
                if ($signed(fft_real) < $signed(frame_min_q))
                    frame_min_q = fft_real;
                if ($signed(fft_imag) < $signed(frame_min_q))
                    frame_min_q = fft_imag;
                if ($signed(fft_real) > $signed(frame_max_q))
                    frame_max_q = fft_real;
                if ($signed(fft_imag) > $signed(frame_max_q))
                    frame_max_q = fft_imag;

                if (fft_bin < output_limit) begin
                    $fwrite(bins_fd,
                        "%0s,%0d,%0d,%0d,%0d,%.10f,%.10f\n",
                        mode_name, frame_count, fft_bin,
                        $signed(fft_real), $signed(fft_imag),
                        $itor($signed(fft_real))/numeric_scale,
                        $itor($signed(fft_imag))/numeric_scale);
                    saved_bin_count <= saved_bin_count + 1;
                end

                if (received_bins == 63) begin
                    $fwrite(frames_fd,
                        "%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                        mode_name, frame_count,
                        $signed(frame_min_q), $signed(frame_max_q),
                        fft_overflow_frame,
                        fft_overflow_stage_frame[0],
                        fft_overflow_stage_frame[1],
                        fft_overflow_stage_frame[2],
                        fft_overflow_stage_frame[3],
                        fft_overflow_stage_frame[4],
                        fft_overflow_stage_frame[5]);
                    $fwrite(frames_fd,
                        ",%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",
                        desired_fir_stage1_saturations,
                        desired_fir_stage2_saturations,
                        desired_fir_stage3_saturations,
                        reference_fir_stage1_saturations,
                        reference_fir_stage2_saturations,
                        reference_fir_stage3_saturations,
                        lms_error_saturations,
                        lms_estimate_saturations,
                        lms_coefficient_saturations,
                        hann_saturations,
                        input_samples,
                        desired_decimated_samples,
                        lms_input_samples);

                    frame_count <= frame_count + 1;
                    if (progress_frames > 0 &&
                        ((frame_count + 1) % progress_frames) == 0)
                        $display("[%0s] progresso: %0d frames",
                            mode_name, frame_count + 1);
                    received_bins <= 0;
                    frame_min_q <= {1'b0, {(DATA_WIDTH-1){1'b1}}};
                    frame_max_q <= {1'b1, {(DATA_WIDTH-1){1'b0}}};
                    fft_overflow_frame <= 0;
                    for (i = 0; i < 6; i = i + 1)
                        fft_overflow_stage_frame[i] <= 0;
                end
                else
                    received_bins <= received_bins + 1;
            end
        end
    end

    initial begin
        reset = 1'b1;
        desired_sample = {DATA_WIDTH{1'b0}};
        desired_valid = 1'b0;
        reference_sample = {DATA_WIDTH{1'b0}};
        reference_valid = 1'b0;
        clear_coefficients = 1'b0;
        fft_ready = 1'b1;
        run_pass = 1'b0;

        input_samples = 0;
        max_frames = 10;
        adapt_samples = 0;
        save_all_bins = 0;
        progress_frames = 10;
        mode_name = "mode";
        numeric_scale = 1 << FRAC_BITS;
        fft_scale_divisor = NORMALIZE ? 64 : 1;
        output_limit = 32;

        if (!$value$plusargs("DESIRED_FILE=%s", desired_file_name) ||
            !$value$plusargs("OUTPUT_BINS_CSV=%s", bins_file_name) ||
            !$value$plusargs("OUTPUT_FRAMES_CSV=%s", frames_file_name) ||
            !$value$plusargs("OUTPUT_REPORT=%s", report_file_name))
            $fatal(1, "Plusargs de arquivos obrigatorios ausentes.");

        if (USE_LMS != 0 &&
            !$value$plusargs("REFERENCE_FILE=%s", reference_file_name))
            $fatal(1, "REFERENCE_FILE e obrigatorio quando USE_LMS=1.");

        void'($value$plusargs("MODE_NAME=%s", mode_name));
        void'($value$plusargs("MAX_FRAMES=%d", max_frames));
        void'($value$plusargs("ADAPT_SAMPLES=%d", adapt_samples));
        void'($value$plusargs("SAVE_ALL_BINS=%d", save_all_bins));
        void'($value$plusargs("PROGRESS_FRAMES=%d", progress_frames));
        output_limit = save_all_bins ? 64 : 32;

        desired_fd = $fopen(desired_file_name, "r");
        if (!desired_fd)
            $fatal(1, "Nao foi possivel abrir DESIRED_FILE.");

        if (USE_LMS != 0) begin
            reference_fd = $fopen(reference_file_name, "r");
            if (!reference_fd)
                $fatal(1, "Nao foi possivel abrir REFERENCE_FILE.");
        end
        else
            reference_fd = 0;

        bins_fd = $fopen(bins_file_name, "w");
        frames_fd = $fopen(frames_file_name, "w");
        report_fd = $fopen(report_file_name, "w");
        if (!bins_fd || !frames_fd || !report_fd)
            $fatal(1, "Nao foi possivel criar arquivo de resultado.");

        $fwrite(bins_fd,
            "mode,frame_index,bin,real_q,imag_q,real_value,imag_value\n");
        $fwrite(frames_fd,
            "mode,frame_index,component_min_q,component_max_q,fft_overflow_components,stage0_overflows,stage1_overflows,stage2_overflows,stage3_overflows,stage4_overflows,stage5_overflows,desired_fir_stage1_saturations_cumulative,desired_fir_stage2_saturations_cumulative,desired_fir_stage3_saturations_cumulative,reference_fir_stage1_saturations_cumulative,reference_fir_stage2_saturations_cumulative,reference_fir_stage3_saturations_cumulative,lms_error_saturations_cumulative,lms_estimate_saturations_cumulative,lms_coefficient_saturations_cumulative,hann_saturations_cumulative,input_samples_consumed,desired_decimated_samples,lms_input_samples\n");

        repeat (5) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        if (max_frames > 0)
            raw_target = DECIMATION_FACTOR *
                (FRAME_SIZE + ((max_frames - 1) * HOP_SIZE));
        else
            raw_target = 0;

        while ((raw_target == 0) || (input_samples < raw_target)) begin
            scan_desired = $fscanf(desired_fd, "%h", desired_word);
            if (scan_desired != 1)
                break;

            if (USE_LMS != 0) begin
                scan_reference =
                    $fscanf(reference_fd, "%h", reference_word);
                if (scan_reference != 1)
                    break;
            end
            else
                reference_word = {DATA_WIDTH{1'b0}};

            send_input_pair($signed(desired_word), $signed(reference_word));
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
        while (frame_count < expected_frames && drain_cycles < 10000000) begin
            @(posedge clk);
            drain_cycles = drain_cycles + 1;
        end

        if (frame_count != expected_frames)
            $fatal(1,
                "Timeout: frames=%0d, esperados=%0d.",
                frame_count, expected_frames);

        // Deixa as atribuicoes nao bloqueantes dos contadores estabilizarem.
        repeat (3) @(posedge clk);

        $fwrite(report_fd, "mode=%0s\n", mode_name);
        $fwrite(report_fd, "data_width=%0d\n", DATA_WIDTH);
        $fwrite(report_fd, "fractional_bits=%0d\n", FRAC_BITS);
        $fwrite(report_fd, "input_sample_rate_hz=%0d\n",
            INPUT_SAMPLE_RATE_HZ);
        $fwrite(report_fd, "decimation_factor=%0d\n", DECIMATION_FACTOR);
        $fwrite(report_fd, "decimated_sample_rate_hz=%0d\n",
            INPUT_SAMPLE_RATE_HZ / DECIMATION_FACTOR);
        $fwrite(report_fd, "frame_size=%0d\n", FRAME_SIZE);
        $fwrite(report_fd, "hop_size=%0d\n", HOP_SIZE);
        $fwrite(report_fd, "frame_duration_ms=%.6f\n",
            (1000.0 * FRAME_SIZE * DECIMATION_FACTOR) /
            INPUT_SAMPLE_RATE_HZ);
        $fwrite(report_fd, "frame_interval_ms=%.6f\n",
            (1000.0 * HOP_SIZE * DECIMATION_FACTOR) /
            INPUT_SAMPLE_RATE_HZ);
        $fwrite(report_fd, "mean_removal=1\n");
        $fwrite(report_fd, "hann_window=1\n");
        $fwrite(report_fd, "normalize=%0d\n", NORMALIZE);
        $fwrite(report_fd, "fft_scale_divisor=%0d\n", fft_scale_divisor);
        $fwrite(report_fd, "use_lms=%0d\n", USE_LMS);
        $fwrite(report_fd, "lms_taps=8\n");
        $fwrite(report_fd, "mu_shift=%0d\n", MU_SHIFT);
        $fwrite(report_fd, "adapt_samples_decimated=%0d\n", adapt_samples);
        $fwrite(report_fd, "frames_processed=%0d\n", frame_count);
        $fwrite(report_fd, "input_samples_consumed=%0d\n", input_samples);
        $fwrite(report_fd, "desired_decimated_samples=%0d\n",
            desired_decimated_samples);
        $fwrite(report_fd, "reference_decimated_samples=%0d\n",
            reference_decimated_samples);
        $fwrite(report_fd, "lms_input_samples=%0d\n", lms_input_samples);
        $fwrite(report_fd, "raw_samples_discarded_by_decimation=%0d\n",
            input_samples % DECIMATION_FACTOR);
        if (expected_decimated_samples >= FRAME_SIZE)
            $fwrite(report_fd,
                "decimated_samples_after_last_complete_hop=%0d\n",
                (expected_decimated_samples - FRAME_SIZE) % HOP_SIZE);
        else
            $fwrite(report_fd,
                "decimated_samples_after_last_complete_hop=%0d\n",
                expected_decimated_samples);
        $fwrite(report_fd, "bins_saved=%0d\n", saved_bin_count);
        $fwrite(report_fd, "desired_fir_stage1_saturations=%0d\n",
            desired_fir_stage1_saturations);
        $fwrite(report_fd, "desired_fir_stage2_saturations=%0d\n",
            desired_fir_stage2_saturations);
        $fwrite(report_fd, "desired_fir_stage3_saturations=%0d\n",
            desired_fir_stage3_saturations);
        $fwrite(report_fd, "reference_fir_stage1_saturations=%0d\n",
            reference_fir_stage1_saturations);
        $fwrite(report_fd, "reference_fir_stage2_saturations=%0d\n",
            reference_fir_stage2_saturations);
        $fwrite(report_fd, "reference_fir_stage3_saturations=%0d\n",
            reference_fir_stage3_saturations);
        $fwrite(report_fd, "lms_error_saturations=%0d\n",
            lms_error_saturations);
        $fwrite(report_fd, "lms_estimate_saturations=%0d\n",
            lms_estimate_saturations);
        $fwrite(report_fd, "lms_coefficient_saturations=%0d\n",
            lms_coefficient_saturations);
        $fwrite(report_fd, "hann_saturations=%0d\n", hann_saturations);
        $fwrite(report_fd, "fft_overflow_components=%0d\n",
            fft_overflow_total);
        $fwrite(report_fd, "fft_overflow_by_stage=%0d,%0d,%0d,%0d,%0d,%0d\n",
            fft_overflow_by_stage[0], fft_overflow_by_stage[1],
            fft_overflow_by_stage[2], fft_overflow_by_stage[3],
            fft_overflow_by_stage[4], fft_overflow_by_stage[5]);
        $fwrite(report_fd, "status=PASS\n");

        run_pass = 1'b1;
        $display("[%0s] PASS: entradas=%0d, decimadas=%0d, frames=%0d, bins=%0d",
            mode_name, input_samples, desired_decimated_samples,
            frame_count, saved_bin_count);

        $fclose(desired_fd);
        if (USE_LMS != 0)
            $fclose(reference_fd);
        $fclose(bins_fd);
        $fclose(frames_fd);
        $fclose(report_fd);
        $finish;
    end

`ifndef SYNTHESIS
    initial begin
        if (!((DATA_WIDTH == 24 && FRAC_BITS == 15) ||
              (DATA_WIDTH == 27 && FRAC_BITS == 16)))
            $fatal(1, "Combinacao DATA_WIDTH/FRAC_BITS nao suportada.");
        if (HOP_SIZE < 1 || HOP_SIZE > 64)
            $fatal(1, "HOP_SIZE deve estar entre 1 e 64.");
    end
`endif

endmodule
