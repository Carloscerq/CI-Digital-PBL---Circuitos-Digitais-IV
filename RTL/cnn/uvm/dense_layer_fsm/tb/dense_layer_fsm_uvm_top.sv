// ---------------------------------------------------------------------
//  dense_layer_fsm_uvm_top  --  DUT + interface + UVM entry point for
//  the CNN's dense (fully-connected) output layer FSM: consumes a
//  256-pixel/8-channel frame and emits one OUT_CLASSES=4-wide logits
//  beat via OUT_CLASSES parallel MAC-based dot products + bias against
//  the trained weight ROM.
//
//  This module owns only the free-running clk (toggling every #5, a
//  10ns period, as in tb_dense_layer_fsm.sv), the DUT/interface
//  instances and the config_db handoff. Reset and the DUT's idle input
//  values are driven by dense_layer_fsm_driver's UVM reset_phase
//  rather than from an `initial` block here, so all interface timing
//  lives inside the phase schedule and the test's stimulus can sit in
//  main_phase, which cannot start before reset_phase has finished. The
//  DUT still sees tb_dense_layer_fsm.sv's sequencing -- reset high
//  across the first two posedges, deasserted mid-cycle -- and m_ready
//  stays with the monitor, which drives it from time 0.
//
//  There's exactly one valid geometry here (DATA_WIDTH=24/FRAC_BITS=16/
//  IN_CHANNELS=8/OUT_CLASSES=4/IN_FEATURES=2048, tied to the trained
//  weights in mem/cnn/dense_*.mem, see dense_layer_fsm_pkg.sv), so no
//  elaboration-time cfg object is needed -- unlike perceptron_uvm_top,
//  nothing about the DUT instance varies from run to run.
//
//  dense_layer_fsm.sv's own $readmemh calls (and
//  dense_layer_fsm_scoreboard.sv's) use paths relative to RTL/, so
//  run_uvm.sh cd's there before invoking xrun -- this module and its DUT
//  instance don't need to know that.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module dense_layer_fsm_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import dense_layer_fsm_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    dense_layer_fsm_if vif (.clk(clk));

    dense_layer_fsm #(
        .DATA_WIDTH (24),
        .FRAC_BITS  (16),
        .IN_CHANNELS(8),
        .OUT_CLASSES(4),
        .IN_FEATURES(2048)
    ) dut (
        .clk    (vif.clk),
        .reset    (vif.reset),
        .s_valid(vif.s_valid),
        .s_ready(vif.s_ready),
        .s_data (vif.s_data),
        .s_last (vif.s_last),
        .m_valid(vif.m_valid),
        .m_ready(vif.m_ready),
        .m_data (vif.m_data),
        .m_last (vif.m_last)
    );

    initial begin
        uvm_config_db #(virtual dense_layer_fsm_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
