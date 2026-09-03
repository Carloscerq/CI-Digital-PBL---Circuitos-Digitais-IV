`timescale 1ns / 1ps

// ============================================================================
// Top Level System -- structural only
// ============================================================================
// Four subsystems, an arbiter, and the wires between them. All sizing comes
// from system_types_pkg; all behaviour lives one level down.
//
//   uart_rx -> sensor_ingestion_subsystem  (UART + elastic FIFO)
//           -> dsp_preprocessing_subsystem (4 channels, shared FFT, skid)
//           -> mlp_inference_path          (MDC + features + MLP)   [snoop]
//           -> cnn_inference_path          (spectrograms + CNN)     [owns ready]
//           -> inference_arbiter
//
// The FFT beat stream forks to both inference paths with a single shared
// accept, driven by cnn_inference_path -- the only consumer that can stall.
// ============================================================================
module top_system #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int FIFO_DEPTH  = 64
)(
    input  logic clk,
    input  logic reset,                 // synchronous, active high

    // UART receive pin -- every sensor value arrives here
    input  logic uart_rx,

    // Decision outputs
    output logic [2:0] status_leds,     // [2]=Critical, [1]=Warning, [0]=Normal
    output logic [system_types_pkg::N_VIB-1:0] sensor_fault_mask,
    output logic       alert_flag,

    // One sticky bit per fault source; see system_types_pkg for the index map
    output system_types_pkg::error_status_t error_status
);

    import system_types_pkg::*;

    localparam CONV2_WEIGHTS_FILE = "../mem/cnn/conv2d_weights.mem";
    localparam CONV2_BIASES_FILE  = "../mem/cnn/conv2d_biases.mem";
    localparam DENSE_WEIGHTS_FILE = "../mem/cnn/dense_weights.mem";
    localparam DENSE_BIASES_FILE  = "../mem/cnn/dense_biases.mem";

    // ------------------------------------------------------------------------
    // Interconnect
    // ------------------------------------------------------------------------
    vib_bus_t  vib_data;
    logic      vib_valid;
    logic      vib_ready;
    aux_bus_t  aux_data;

    fft_beat_t fft_beat;
    logic      fft_beat_valid;
    logic      fft_beat_ready;
    logic      fft_frame_done;

    logic [1:0] mlp_class_idx;
    logic       mlp_done;

    sample_t cnn_normal, cnn_unbalance, cnn_misalign, cnn_bearing;
    logic    cnn_valid;

    logic err_uart_frame, err_vib_overrun, err_mlp_drop;
    logic err_spec_desync, err_mdc_overrun, err_cnn_stall;

    // ------------------------------------------------------------------------
    // Ingestion
    // ------------------------------------------------------------------------
    sensor_ingestion_subsystem #(
        .CLK_FREQ_HZ       (CLK_FREQ_HZ),
        .BAUD_RATE         (BAUD_RATE),
        .FIFO_DEPTH        (FIFO_DEPTH),
        .IDLE_TIMEOUT_BYTES(4)
    ) u_ingestion (
        .clk        (clk),
        .reset      (reset),
        .uart_rx    (uart_rx),
        .m_vib_data (vib_data),
        .m_vib_valid(vib_valid),
        .m_vib_ready(vib_ready),
        .aux_data   (aux_data),
        .frame_error(err_uart_frame),
        .vib_overrun(err_vib_overrun)
    );

    // ------------------------------------------------------------------------
    // Signal processing
    // ------------------------------------------------------------------------
    dsp_preprocessing_subsystem #(
        .NORMALIZE(1),
        .HOP_SIZE (64),
        .FIR_STAGE1_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage1_decim4_q117.bin"),
        .FIR_STAGE2_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage2_decim4_q117.bin"),
        .FIR_STAGE3_FILE("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/fir/stage3_decim2_q117.bin"),
        .HANN_FILE      ("../FFT/model_sim_four_modes_quartus_shared_fft/coefficients/windowing/hann_64_q117.bin")
    ) u_dsp (
        .clk         (clk),
        .reset       (reset),
        .s_vib_data  (vib_data),
        .s_vib_valid (vib_valid),
        .s_vib_ready (vib_ready),
        .m_beat      (fft_beat),
        .m_valid     (fft_beat_valid),
        .m_ready     (fft_beat_ready),
        .m_frame_done(fft_frame_done)
    );

    // ------------------------------------------------------------------------
    // Path A: MLP
    // ------------------------------------------------------------------------
    mlp_inference_path #(
        .MDC_K_MAX(26),
        .MDC_K_MIN(2),
        .MDC_PEAKS(3)
    ) u_mlp_path (
        .clk          (clk),
        .reset        (reset),
        .s_beat       (fft_beat),
        .s_valid      (fft_beat_valid),
        .s_ready      (fft_beat_ready),
        .s_frame_done (fft_frame_done),
        .aux_data     (aux_data),
        .mlp_class_idx(mlp_class_idx),
        .mlp_done     (mlp_done),
        .mdc_k0       (),
        .mdc_valid    (),
        .mdc_overrun  (err_mdc_overrun),
        .frame_dropped(err_mlp_drop)
    );

    // ------------------------------------------------------------------------
    // Path B: CNN. Owns the shared accept.
    // ------------------------------------------------------------------------
    cnn_inference_path #(
        .CONV2_WEIGHTS_FILE(CONV2_WEIGHTS_FILE),
        .CONV2_BIASES_FILE (CONV2_BIASES_FILE),
        .DENSE_WEIGHTS_FILE(DENSE_WEIGHTS_FILE),
        .DENSE_BIASES_FILE (DENSE_BIASES_FILE)
    ) u_cnn_path (
        .clk              (clk),
        .reset            (reset),
        .s_beat           (fft_beat),
        .s_valid          (fft_beat_valid),
        .s_ready          (fft_beat_ready),
        .cnn_normal       (cnn_normal),
        .cnn_unbalance    (cnn_unbalance),
        .cnn_misalign     (cnn_misalign),
        .cnn_bearing      (cnn_bearing),
        .cnn_valid        (cnn_valid),
        .spec_desync_error(err_spec_desync),
        .cnn_stall_event  (err_cnn_stall)
    );

    // ------------------------------------------------------------------------
    // Decision
    // ------------------------------------------------------------------------
    inference_arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .N_SENSORS (N_VIB)
    ) u_inference_arbiter (
        .clk              (clk),
        .reset            (reset),
        .mlp_class_idx    (mlp_class_idx),
        .mlp_done         (mlp_done),
        .cnn_normal       (cnn_normal),
        .cnn_unbalance    (cnn_unbalance),
        .cnn_misalign     (cnn_misalign),
        .cnn_bearing      (cnn_bearing),
        .cnn_valid        (cnn_valid),
        .status_leds      (status_leds),
        .sensor_fault_mask(sensor_fault_mask),
        .alert_flag       (alert_flag)
    );

    // ------------------------------------------------------------------------
    // Health
    // ------------------------------------------------------------------------
    // One sticky bit per source. Some subsystems already latch their own flag;
    // latching again here costs six flip-flops and makes the whole bus behave
    // identically, so a SignalTap capture never has to know which is which.
    logic [N_ERR-1:0] err_raw;
    assign err_raw[ERR_UART_FRAME]  = err_uart_frame;
    assign err_raw[ERR_VIB_OVERRUN] = err_vib_overrun;
    assign err_raw[ERR_MLP_DROP]    = err_mlp_drop;
    assign err_raw[ERR_SPEC_DESYNC] = err_spec_desync;
    assign err_raw[ERR_MDC_OVERRUN] = err_mdc_overrun;
    assign err_raw[ERR_CNN_STALL]   = err_cnn_stall;

    always_ff @(posedge clk) begin
        if (reset) error_status <= '0;
        else       error_status <= error_status | err_raw;
    end

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != mlp_weights_pkg::ACC_WIDTH)
            $fatal(1, "[top_system] DATA_WIDTH (%0d) != mlp ACC_WIDTH (%0d).",
                   DATA_WIDTH, mlp_weights_pkg::ACC_WIDTH);
        if (mlp_weights_pkg::N_BINS != N_VIB * SPEC_BINS)
            $fatal(1, "[top_system] N_BINS (%0d) != N_VIB*SPEC_BINS (%0d).",
                   mlp_weights_pkg::N_BINS, N_VIB * SPEC_BINS);
        if (mlp_weights_pkg::N_IN != mlp_weights_pkg::N_BINS + mlp_weights_pkg::N_EXTRA)
            $fatal(1, "[top_system] N_IN != N_BINS + N_EXTRA.");
    end
    // synthesis translate_on

endmodule
