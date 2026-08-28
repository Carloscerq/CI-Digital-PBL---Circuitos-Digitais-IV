// ---------------------------------------------------------------------
//  preprocess_lms_fft_uvm_top  --  DUT + interface + UVM entry point
//  for the FFT preprocessing pipeline's top-level module,
//  preprocess_lms_fft_four_modes (fir_decimator_32_dualmode -> [
//  lms_filter_8tap_dualmode, not instantiated at USE_LMS=0] ->
//  sample_buffer_64_hop_dualmode -> mean_remover_64_dualmode ->
//  hann_window_64_dualmode -> fft_64_dualmode).
//
//  Clock: free-running, 10ns period (`always #5 clk = ~clk;`), same
//  period every other UVM testbench in this repo uses.
//
//  Reset: held high then dropped after #22 (so it deasserts mid-cycle),
//  mirroring smma_cnn_top_uvm_top.sv's own reset sequencing -- no
//  existing FFT-pipeline tb (tb_fft_lms_dataset.sv) was found to give a
//  more specific convention to follow, so this repo's other UVM
//  top-level testbench's convention was reused.
//
//  USE_LMS=0 -- the DUT's simpler single-input-stream mode, and the
//  primary/required configuration for this testbench (see
//  preprocess_lms_fft_pkg.sv's header for the full scope rationale).
//  reference_sample/reference_valid/adapt_enable/clear_coefficients are
//  tied to inert (0) values directly here, and reference_ready plus
//  every USE_LMS=1-only diagnostic output (reference_decimated_event,
//  lms_input_event, lms_output_event, reference_fir_stage*_saturation_
//  event, lms_*_saturated, desired_decimated_event) are left
//  unconnected -- all of them are tied to constants or simply unused by
//  the DUT itself in the gen_no_lms generate branch (see
//  preprocess_lms_fft_four_modes.sv), so there is nothing meaningful
//  for this protocol-level testbench to observe on them.
//
//  There's exactly one configuration exercised here (see
//  preprocess_lms_fft_pkg.sv), so no elaboration-time cfg object is
//  needed, mirroring smma_cnn_top_uvm_top.sv/line_buffer_3x3_uvm_top.sv.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module preprocess_lms_fft_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import preprocess_lms_fft_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    preprocess_lms_fft_if vif (.clk(clk));

    preprocess_lms_fft_four_modes #(
        .DATA_WIDTH (24),
        .FRAC_BITS  (15),
        .NORMALIZE  (1),
        .USE_LMS    (0),
        .MU_SHIFT   (16),
        .HOP_SIZE   (8)
    ) dut (
        .clk                                     (vif.clk),
        .reset                                   (vif.reset),

        .desired_sample                          (vif.desired_sample),
        .desired_valid                           (vif.desired_valid),
        .desired_ready                           (vif.desired_ready),
        .reference_sample                        ('0),
        .reference_valid                         (1'b0),
        .reference_ready                         (),

        .adapt_enable                            (1'b0),
        .clear_coefficients                      (1'b0),

        .fft_valid                               (vif.fft_valid),
        .fft_ready                               (vif.fft_ready),
        .fft_bin                                 (vif.fft_bin),
        .fft_real                                (vif.fft_real),
        .fft_imag                                (vif.fft_imag),
        .fft_done                                (vif.fft_done),
        .pipeline_busy                           (vif.pipeline_busy),

        .desired_decimated_event                 (),
        .reference_decimated_event               (),
        .lms_input_event                         (),
        .lms_output_event                        (),
        .desired_fir_stage1_saturation_event     (vif.desired_fir_stage1_saturation_event),
        .desired_fir_stage2_saturation_event     (vif.desired_fir_stage2_saturation_event),
        .desired_fir_stage3_saturation_event     (vif.desired_fir_stage3_saturation_event),
        .reference_fir_stage1_saturation_event   (),
        .reference_fir_stage2_saturation_event   (),
        .reference_fir_stage3_saturation_event   (),
        .lms_error_saturated                     (),
        .lms_estimate_saturated                  (),
        .lms_coefficient_saturated               (),
        .hann_saturation_event                   (vif.hann_saturation_event),
        .fft_overflow_event                      (vif.fft_overflow_event),
        .fft_overflow_stage                      (vif.fft_overflow_stage),
        .fft_overflow_components                 (vif.fft_overflow_components)
    );

    initial begin
        vif.reset          = 1'b1;
        vif.desired_valid  = 1'b0;
        vif.desired_sample = '0;
        vif.fft_ready      = 1'b0;

        #22 vif.reset = 1'b0;

        uvm_config_db #(virtual preprocess_lms_fft_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
