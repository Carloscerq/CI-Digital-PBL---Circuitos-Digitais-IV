// ---------------------------------------------------------------------
//  spectrogram_generator_uvm_top  --  DUT + interface + UVM entry point
//  for the spectrogram ping-pong double buffer. This module owns only
//  the free-running clk (toggling every #5, a 10ns period, as in
//  tb_spectrogram_generator.sv), the DUT/interface instances and the
//  config_db handoff. Reset and the DUT's idle input values are driven
//  by spectrogram_generator_driver's UVM reset_phase rather than from
//  an `initial` block here, so all interface timing lives inside the
//  phase schedule and the test's stimulus can sit in main_phase, which
//  cannot start before reset_phase has finished. The DUT still sees
//  tb_spectrogram_generator.sv's sequencing -- reset high across the
//  first two posedges, deasserted mid-cycle -- and m_axis_ready stays
//  with the monitor, which drives it from time 0.
//
//  No cfg object is needed: like smma_cnn_top_uvm_top.sv, there's
//  exactly one valid geometry here (see spectrogram_generator_pkg.sv),
//  so nothing about the DUT instance varies from run to run.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module spectrogram_generator_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import spectrogram_generator_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // matches tb_spectrogram_generator.sv's period

    spectrogram_generator_if vif (.clk(clk));

    spectrogram_generator #(
        .DATA_WIDTH            (24),
        .BINS_PER_FRAME        (32),
        .FRAMES_PER_SPECTROGRAM(32)
    ) dut (
        .clk     (vif.clk),
        .reset   (vif.reset),
        .s_valid (vif.s_axis_valid),
        .s_ready (vif.s_axis_ready),
        .s_data  (vif.s_axis_data),
        .s_last  (vif.s_axis_last),
        .m_valid (vif.m_axis_valid),
        .m_ready (vif.m_axis_ready),
        .m_data  (vif.m_axis_data),
        .m_last  (vif.m_axis_last)
    );

    initial begin
        uvm_config_db #(virtual spectrogram_generator_if)::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
