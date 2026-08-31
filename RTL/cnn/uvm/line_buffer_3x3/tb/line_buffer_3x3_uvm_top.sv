// ---------------------------------------------------------------------
//  line_buffer_3x3_uvm_top  --  DUT + interface + UVM entry point for
//  the CNN's line-buffer / sliding-window generator.
//
//  This module owns only the free-running clk (toggling every #5, a
//  10ns period, as in tb_line_buffer_3x3.sv), the DUT/interface
//  instances and the config_db handoff. Reset and the DUT's idle input
//  values are driven by line_buffer_3x3_driver's UVM reset_phase
//  rather than from an `initial` block here, so all interface timing
//  lives inside the phase schedule and the test's stimulus can sit in
//  main_phase, which cannot start before reset_phase has finished. The
//  DUT still sees tb_line_buffer_3x3.sv's sequencing -- reset high
//  across the first two posedges, deasserted mid-cycle -- and m_ready
//  stays with the monitor, which drives it from time 0.
//
//  There's exactly one valid geometry here (DATA_WIDTH=24/IMG_WIDTH=32/
//  IMG_HEIGHT=32/IN_CHANNELS=4, see line_buffer_3x3_pkg.sv), so no
//  elaboration-time cfg object is needed -- unlike perceptron_uvm_top,
//  nothing about the DUT instance varies from run to run.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module line_buffer_3x3_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import line_buffer_3x3_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    line_buffer_3x3_if vif (.clk(clk));

    line_buffer_3x3 #(
        .DATA_WIDTH  (24),
        .IMG_WIDTH   (32),
        .IMG_HEIGHT  (32),
        .IN_CHANNELS (4)
    ) dut (
        .clk     (vif.clk),
        .reset     (vif.reset),
        .s_valid (vif.s_valid),
        .s_ready (vif.s_ready),
        .s_data  (vif.s_data),
        .s_last  (vif.s_last),
        .m_valid (vif.m_valid),
        .m_ready (vif.m_ready),
        .m_window(vif.m_window),
        .m_last  (vif.m_last)
    );

    initial begin
        uvm_config_db #(virtual line_buffer_3x3_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
