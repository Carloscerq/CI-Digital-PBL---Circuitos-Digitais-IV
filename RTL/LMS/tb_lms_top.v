`timescale 1ns/1ps

module tb_lms_top;

    parameter WIDTH = 24;
    parameter FRAC  = 15;

    reg clk;
    reg reset;
    reg signed [WIDTH-1:0] data_in;
    reg data_valid;
    wire data_ready;
    wire block_ready;
    reg fft_begin;
    reg fft_rd_en;
    reg [5:0] fft_rd_addr;
    wire signed [WIDTH-1:0] fft_data_out;
    wire fft_data_valid;
    reg fft_done;
    wire signed [WIDTH-1:0] lms_error;

    integer i;
    integer k;
    integer noise_i;
    integer sample_i;
    integer outfile;

    real pi;
    real signal_r;
    real noise_r;
    real sample_r;

    lms_top #(
        .WIDTH(WIDTH),
        .FRAC(FRAC),
        .MU_Q(24'sd256)
    ) dut (
        .clk(clk),
        .reset(reset),
        .data_in(data_in),
        .data_valid(data_valid),
        .data_ready(data_ready),
        .block_ready(block_ready),
        .fft_begin(fft_begin),
        .fft_rd_en(fft_rd_en),
        .fft_rd_addr(fft_rd_addr),
        .fft_data_out(fft_data_out),
        .fft_data_valid(fft_data_valid),
        .fft_done(fft_done),
        .lms_error(lms_error)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        data_in = 0;
        data_valid = 1'b0;
        fft_begin = 1'b0;
        fft_rd_en = 1'b0;
        fft_rd_addr = 6'd0;
        fft_done = 1'b0;

        pi = 3.14159265358979323846;
        outfile = $fopen("fft_input_samples.txt", "w");

        #30;
        reset = 1'b0;

        for (i = 0; i < 256; i = i + 1) begin
            signal_r = 0.60 * $sin(2.0 * pi * 5.0 * i / 64.0);
            noise_i = ($random % 9830);
            noise_r = noise_i / 32768.0;
            sample_r = signal_r + noise_r;
            sample_i = $rtoi(sample_r * 32768.0);

            while (!data_ready)
                @(posedge clk);

            @(negedge clk);
            data_in = sample_i;
            data_valid = 1'b1;

            @(negedge clk);
            data_valid = 1'b0;

            if (block_ready) begin
                fft_begin = 1'b1;
                @(negedge clk);
                fft_begin = 1'b0;

                for (k = 0; k < 64; k = k + 1) begin
                    fft_rd_addr = k;
                    fft_rd_en = 1'b1;
                    @(posedge clk);
                    #1;
                    if (fft_data_valid)
                        $fwrite(outfile, "%0d\n", $signed(fft_data_out));
                    @(negedge clk);
                end

                fft_rd_en = 1'b0;
                fft_done = 1'b1;
                @(negedge clk);
                fft_done = 1'b0;
            end
        end

        #100;
        $fclose(outfile);
        $stop;
    end

endmodule
