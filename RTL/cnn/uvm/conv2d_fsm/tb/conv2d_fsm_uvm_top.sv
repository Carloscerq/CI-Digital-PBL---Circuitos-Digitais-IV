// ---------------------------------------------------------------------
//  conv2d_fsm_uvm_top  --  DUT + interface + UVM entry point for the
//  CNN's convolution FSM (CHANNELS=8 parallel MAC-based convolutions +
//  bias + ReLU per 3x3xIN_CHANNELS window).
//
//  This module owns only the free-running clk (toggling every #5, a
//  10ns period, as in tb_conv2d_fsm.sv), the DUT/interface instances
//  and the config_db handoff. Reset and the DUT's idle input values
//  are driven by conv2d_fsm_driver's UVM reset_phase rather than from
//  an `initial` block here, so all interface timing lives inside the
//  phase schedule and the test's stimulus can sit in main_phase, which
//  cannot start before reset_phase has finished. The DUT still sees
//  tb_conv2d_fsm.sv's sequencing -- reset high across the first two
//  posedges, deasserted mid-cycle -- and m_ready stays with the
//  monitor, which drives it from time 0.
//
//  There's exactly one valid geometry here (DATA_WIDTH=24/FRAC_BITS=16/
//  CHANNELS=8/IN_CHANNELS=4, tied to the trained weights in
//  mem/cnn/conv2d_*.mem, see conv2d_fsm_pkg.sv), so no elaboration-time
//  cfg object is needed -- unlike perceptron_uvm_top, nothing about the
//  DUT instance varies from run to run.
//
//  conv2d_fsm.sv's own $readmemh calls (and conv2d_fsm_scoreboard.sv's)
//  use paths relative to RTL/, so run_uvm.sh cd's there before invoking
//  xrun -- this module and its DUT instance don't need to know that.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module conv2d_fsm_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import conv2d_fsm_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    conv2d_fsm_if vif (.clk(clk));

    conv2d_fsm #(
        .DATA_WIDTH (24),
        .FRAC_BITS  (16),
        .CHANNELS   (8),
        .IN_CHANNELS(4)
    ) dut (
        .clk    (vif.clk),
        .reset    (vif.reset),
        .s_valid(vif.s_valid),
        .s_ready(vif.s_ready),
        .s_window(vif.s_window),
        .s_last (vif.s_last),
        .m_valid(vif.m_valid),
        .m_ready(vif.m_ready),
        .m_data (vif.m_data),
        .m_last (vif.m_last)
    );

    initial begin
        uvm_config_db #(virtual conv2d_fsm_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
