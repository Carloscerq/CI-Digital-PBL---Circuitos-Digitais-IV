// ---------------------------------------------------------------------
//  preprocess_lms_fft_if  --  connects the UVM agent to
//  preprocess_lms_fft_four_modes, the FFT preprocessing pipeline's
//  top-level module (fir_decimator_32_dualmode -> [lms_filter_8tap_
//  dualmode, unused here] -> sample_buffer_64_hop_dualmode ->
//  mean_remover_64_dualmode -> hann_window_64_dualmode ->
//  fft_64_dualmode).
//
//  This is a protocol/integration-level testbench (see
//  preprocess_lms_fft_scoreboard.sv), fixed at USE_LMS=0 -- the DUT's
//  simpler single-input-stream mode (see the pipeline module: with
//  USE_LMS==0, reference_ready is tied to 1'b0 and reference_sample/
//  reference_valid/adapt_enable/clear_coefficients are simply unused).
//  Those ports are therefore NOT carried on this interface at all --
//  they're tied off directly in preprocess_lms_fft_uvm_top.sv, which
//  instantiates the DUT -- only the desired_* stream, the fft_* output
//  stream, pipeline_busy, and the diagnostic events that are actually
//  meaningful in USE_LMS=0 mode (the desired-side FIR-stage saturation
//  events, the Hann-window saturation event, and the FFT overflow
//  event/detail) are here. The USE_LMS=1 (dual-stream LMS) diagnostic
//  ports (reference_fir_stage*_saturation_event, lms_*_saturated,
//  lms_input_event, lms_output_event, reference_decimated_event) are
//  all tied to 1'b0 by the DUT itself in that mode (see the
//  preprocess_lms_fft_four_modes gen_no_lms generate block) and are
//  out of scope for this testbench.
// ---------------------------------------------------------------------
interface preprocess_lms_fft_if (
    input logic clk
);

    localparam int DATA_WIDTH = 24;

    logic reset;

    // Slave (input) side: one desired_sample beat per accepted
    // handshake, driven continuously (desired_valid held high) by
    // preprocess_lms_fft_driver.sv.
    logic                          desired_valid;
    logic                          desired_ready;
    logic signed [DATA_WIDTH-1:0]  desired_sample;

    // Master (output) side: one complex FFT bin per accepted handshake,
    // 64 bins (bin 0..63, in order) per completed frame, terminated by
    // a one-cycle fft_done pulse. fft_ready is driven by
    // preprocess_lms_fft_monitor.sv with randomized backpressure.
    logic                          fft_valid;
    logic                          fft_ready;
    logic [5:0]                    fft_bin;
    logic signed [DATA_WIDTH-1:0]  fft_real;
    logic signed [DATA_WIDTH-1:0]  fft_imag;
    logic                          fft_done;

    logic                          pipeline_busy;

    // Diagnostic events meaningful in USE_LMS=0 mode -- see
    // preprocess_lms_fft_monitor.sv for the "nothing pathological
    // happened" sanity checks built on these.
    logic                          desired_fir_stage1_saturation_event;
    logic                          desired_fir_stage2_saturation_event;
    logic                          desired_fir_stage3_saturation_event;
    logic                          hann_saturation_event;
    logic                          fft_overflow_event;
    logic [2:0]                    fft_overflow_stage;
    logic [2:0]                    fft_overflow_components;

endinterface
