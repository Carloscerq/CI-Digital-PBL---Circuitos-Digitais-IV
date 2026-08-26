`timescale 1ns / 1ps

// ============================================================================
// Top Level System
// ============================================================================
module top_system #(
    parameter int DATA_WIDTH = 24
)(
    input  logic clk,
    input  logic reset_n, // Asynchronous active-low reset
    
    // SPI Pins
    input  logic spi_serial_clock,
    input  logic spi_slave_select_n,
    input  logic spi_mosi,
    output logic spi_miso,
    
    // External Sensor Data (GCD, Temp, Voltage, etc.)
    input  logic signed [DATA_WIDTH-1:0] ext_gcd,
    input  logic signed [DATA_WIDTH-1:0] ext_temperature,
    input  logic signed [DATA_WIDTH-1:0] ext_voltage,
    input  logic signed [DATA_WIDTH-1:0] ext_other,
    
    // Arbiter Outputs
    output logic [2:0] status_leds,
    output logic alert_flag
);

    // Reset Distribution
    logic reset;
    assign reset = ~reset_n; // Synchronous active-high reset derived from reset_n

    // ------------------------------------------------------------------------
    // SPI Data Ingestion
    // ------------------------------------------------------------------------
    logic [7:0] spi_data_out;
    logic       spi_data_valid;
    logic       spi_busy;
    
    spi_slave #(
        .SIZE(8),
        .CPOL(1'b0),
        .CPHA(1'b0)
    ) u_spi_slave (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(8'd0), // Not transmitting data back for now
        .data_out(spi_data_out),
        .data_valid(spi_data_valid),
        .busy(spi_busy),
        .serial_clock(spi_serial_clock),
        .slave_in_controller_out(spi_mosi),
        .controller_in_slave_out(spi_miso),
        .slave_select_n(spi_slave_select_n)
    );

    logic [DATA_WIDTH-1:0] deserialized_data;
    logic deserialized_valid;
    logic fft_desired_ready;

    spi_rx_deserializer u_deserializer (
        .clk(clk),
        .reset_n(reset_n),
        .spi_data(spi_data_out),
        .spi_valid(spi_data_valid),
        .out_data(deserialized_data),
        .out_valid(deserialized_valid),
        .out_ready(fft_desired_ready)
    );

    // ------------------------------------------------------------------------
    // Signal Processing (FFT + LMS)
    // ------------------------------------------------------------------------
    logic fft_valid;
    logic [5:0] fft_bin;
    logic signed [DATA_WIDTH-1:0] fft_real;
    logic signed [DATA_WIDTH-1:0] fft_imag;
    logic fft_done;
    
    preprocess_lms_fft_four_modes #(
        .DATA_WIDTH(DATA_WIDTH),
        .USE_LMS(1) // Assuming LMS is enabled by default
    ) u_fft_pipeline (
        .clk(clk),
        .reset(reset),
        
        .desired_sample(deserialized_data),
        .desired_valid(deserialized_valid),
        .desired_ready(fft_desired_ready),
        
        .reference_sample({DATA_WIDTH{1'b0}}), // No reference signal provided currently
        .reference_valid(deserialized_valid),
        .reference_ready(),
        
        .adapt_enable(1'b1),
        .clear_coefficients(1'b0),
        
        .fft_valid(fft_valid),
        .fft_ready(1'b1), // Always ready to receive FFT output internally
        .fft_bin(fft_bin),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_done(fft_done),
        .pipeline_busy(),
        
        // Debug and event flags left unconnected for brevity
        .desired_decimated_event(),
        .reference_decimated_event(),
        .lms_input_event(),
        .lms_output_event(),
        .desired_fir_stage1_saturation_event(),
        .desired_fir_stage2_saturation_event(),
        .desired_fir_stage3_saturation_event(),
        .reference_fir_stage1_saturation_event(),
        .reference_fir_stage2_saturation_event(),
        .reference_fir_stage3_saturation_event(),
        .lms_error_saturated(),
        .lms_estimate_saturated(),
        .lms_coefficient_saturated(),
        .hann_saturation_event(),
        .fft_overflow_event(),
        .fft_overflow_stage(),
        .fft_overflow_components()
    );

    // ------------------------------------------------------------------------
    // Path A: MLP Data Fork
    // ------------------------------------------------------------------------
    logic signed [DATA_WIDTH-1:0] mlp_features [132];
    logic mlp_start;
    logic mlp_busy_internal;

    fft_to_mlp_collector #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_IN(132)
    ) u_feature_collector (
        .clk(clk),
        .reset_n(reset_n),
        .fft_valid(fft_valid),
        .fft_bin(fft_bin),
        .fft_real(fft_real),
        .fft_imag(fft_imag),
        .fft_done(fft_done),
        .ext_gcd(ext_gcd),
        .ext_temperature(ext_temperature),
        .ext_voltage(ext_voltage),
        .ext_other(ext_other),
        .mlp_features(mlp_features),
        .mlp_start(mlp_start),
        .mlp_busy(mlp_busy_internal)
    );

    logic signed [DATA_WIDTH-1:0] mlp_logits [4];
    logic [1:0] mlp_class_idx;
    logic mlp_done;

    mlp u_mlp (
        .clk(clk),
        .rst_n(reset_n),
        .start(mlp_start),
        .features(mlp_features),
        .logits(mlp_logits),
        .class_idx(mlp_class_idx),
        .busy(mlp_busy_internal),
        .done(mlp_done)
    );

    // ------------------------------------------------------------------------
    // Path B: Spectrogram & CNN Fork
    // ------------------------------------------------------------------------
    logic spec_axis_valid;
    logic spec_axis_ready;
    logic signed [DATA_WIDTH-1:0] spec_axis_data;
    logic spec_axis_last;

    fft_to_axi_adapter #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_fft_to_spec_adapter (
        .clk(clk),
        .rst(reset),
        .fft_valid(fft_valid),
        .fft_bin(fft_bin),
        .fft_real(fft_real),
        .s_axis_valid(spec_axis_valid),
        .s_axis_ready(spec_axis_ready),
        .s_axis_data(spec_axis_data),
        .s_axis_last(spec_axis_last)
    );

    logic spec_m_valid;
    logic spec_m_ready;
    logic signed [DATA_WIDTH-1:0] spec_m_data;
    logic spec_m_last;

    spectrogram_generator #(
        .DATA_WIDTH(DATA_WIDTH),
        .BINS_PER_FRAME(32),
        .FRAMES_PER_SPECTROGRAM(32)
    ) u_spectrogram (
        .clk(clk),
        .rst(reset),
        .s_axis_valid(spec_axis_valid),
        .s_axis_ready(spec_axis_ready),
        .s_axis_data(spec_axis_data),
        .s_axis_last(spec_axis_last),
        .m_axis_valid(spec_m_valid),
        .m_axis_ready(spec_m_ready),
        .m_axis_data(spec_m_data),
        .m_axis_last(spec_m_last)
    );

    logic cnn_s_valid;
    logic cnn_s_ready;
    logic signed [DATA_WIDTH-1:0] cnn_s_data [0:3];
    logic cnn_s_last;

    spectrogram_to_cnn_adapter #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_spec_to_cnn_adapter (
        .m_axis_valid(spec_m_valid),
        .m_axis_ready(spec_m_ready),
        .m_axis_data(spec_m_data),
        .m_axis_last(spec_m_last),
        .s_axis_valid(cnn_s_valid),
        .s_axis_ready(cnn_s_ready),
        .s_axis_data(cnn_s_data),
        .s_axis_last(cnn_s_last)
    );

    logic signed [DATA_WIDTH-1:0] cnn_normal;
    logic signed [DATA_WIDTH-1:0] cnn_unbalance;
    logic signed [DATA_WIDTH-1:0] cnn_misalign;
    logic signed [DATA_WIDTH-1:0] cnn_bearing;
    logic cnn_valid;

    smma_cnn_top #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_cnn (
        .clk(clk),
        .rst(reset),
        .s_axis_valid(cnn_s_valid),
        .s_axis_ready(cnn_s_ready),
        .s_axis_data(cnn_s_data),
        .s_axis_last(cnn_s_last),
        .m_axis_valid(cnn_valid),
        .m_axis_ready(1'b1), // Always ready to receive CNN inference
        .m_axis_data_normal(cnn_normal),
        .m_axis_data_unbalance(cnn_unbalance),
        .m_axis_data_misalign(cnn_misalign),
        .m_axis_data_bearing(cnn_bearing),
        .m_axis_last()
    );

    // ------------------------------------------------------------------------
    // Decision Logic: Inference Arbiter
    // ------------------------------------------------------------------------
    inference_arbiter #(
        .DATA_WIDTH(DATA_WIDTH)
    ) u_inference_arbiter (
        .clk(clk),
        .reset_n(reset_n),
        .mlp_class_idx(mlp_class_idx),
        .mlp_done(mlp_done),
        .cnn_normal(cnn_normal),
        .cnn_unbalance(cnn_unbalance),
        .cnn_misalign(cnn_misalign),
        .cnn_bearing(cnn_bearing),
        .cnn_valid(cnn_valid),
        .status_leds(status_leds),
        .alert_flag(alert_flag)
    );

endmodule
