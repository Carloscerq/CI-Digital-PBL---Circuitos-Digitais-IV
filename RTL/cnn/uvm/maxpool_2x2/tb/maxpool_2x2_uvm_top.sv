// ---------------------------------------------------------------------
//  maxpool_2x2_uvm_top  --  DUT + interface + UVM entry point for the
//  CNN's 2x2 max-pooling unit.
//
//  This module owns only the free-running clk (toggling every #5, a
//  10ns period, as in tb_maxpool_2x2.sv), the DUT/interface instances
//  and the config_db handoff. Reset and the DUT's idle input values are
//  driven by maxpool_2x2_driver's UVM reset_phase rather than from an
//  `initial` block here, so all interface timing lives inside the phase
//  schedule and the test's stimulus can sit in main_phase, which cannot
//  start before reset_phase has finished. The DUT still sees
//  tb_maxpool_2x2.sv's sequencing -- reset high across the first two
//  posedges, deasserted mid-cycle -- and m_ready stays with the
//  monitor, which drives it from time 0.
//
//  There's exactly one valid geometry here (DATA_WIDTH=24/IMG_WIDTH=32/
//  CHANNELS=8, see maxpool_2x2_pkg.sv), so no elaboration-time cfg
//  object is needed -- nothing about the DUT instance varies from run
//  to run.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module maxpool_2x2_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import maxpool_2x2_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    maxpool_2x2_if vif (.clk(clk));

    maxpool_2x2 #(
        .DATA_WIDTH (24),
        .IMG_WIDTH  (32),
        .CHANNELS   (8)
    ) dut (
        .clk     (vif.clk),
        .reset     (vif.reset),
        .s_valid (vif.s_valid),
        .s_ready (vif.s_ready),
        .s_data  (vif.s_data),
        .s_last  (vif.s_last),
        .m_valid (vif.m_valid),
        .m_ready (vif.m_ready),
        .m_data  (vif.m_data),
        .m_last  (vif.m_last)
    );

    initial begin
        uvm_config_db #(virtual maxpool_2x2_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
