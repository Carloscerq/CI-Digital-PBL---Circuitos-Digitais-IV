module lms_top #(
    parameter WIDTH = 24,
    parameter FRAC  = 15,
    parameter signed [WIDTH-1:0] MU_Q = 24'sd256
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire signed [WIDTH-1:0] data_in,
    input  wire                    data_valid,
    output wire                    data_ready,
    output wire                    block_ready,
    input  wire                    fft_begin,
    input  wire                    fft_rd_en,
    input  wire [5:0]              fft_rd_addr,
    output wire signed [WIDTH-1:0] fft_data_out,
    output wire                    fft_data_valid,
    input  wire                    fft_done,
    output wire signed [WIDTH-1:0] lms_error
);

    wire signed [WIDTH-1:0] lms_filtered;
    wire lms_filtered_valid;
    wire buffer_ready;

    lms #(
        .WIDTH(WIDTH),
        .FRAC(FRAC),
        .MU_Q(MU_Q)
    ) u_lms (
        .clk(clk),
        .reset(reset),
        .sample_in(data_in),
        .sample_valid(data_valid),
        .sample_ready(data_ready),
        .filtered_out(lms_filtered),
        .error_out(lms_error),
        .filtered_valid(lms_filtered_valid),
        .filtered_ready(buffer_ready)
    );

    buffer #(
        .WIDTH(WIDTH)
    ) u_buffer (
        .clk(clk),
        .reset(reset),
        .sample_in(lms_filtered),
        .sample_valid(lms_filtered_valid),
        .sample_ready(buffer_ready),
        .block_ready(block_ready),
        .fft_begin(fft_begin),
        .fft_rd_en(fft_rd_en),
        .fft_rd_addr(fft_rd_addr),
        .fft_data_out(fft_data_out),
        .fft_data_valid(fft_data_valid),
        .fft_done(fft_done)
    );

endmodule
