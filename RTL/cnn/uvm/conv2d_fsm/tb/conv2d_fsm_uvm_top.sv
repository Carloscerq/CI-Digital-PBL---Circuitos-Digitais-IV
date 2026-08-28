// ---------------------------------------------------------------------
//  conv2d_fsm_uvm_top  --  DUT + interface + UVM entry point for the
//  CNN's convolution FSM (CHANNELS=8 parallel MAC-based convolutions +
//  bias + ReLU per 3x3xIN_CHANNELS window).
//
//  Clock and reset sequencing mirror tb_conv2d_fsm.sv exactly: a
//  free-running clk toggling every #5 (10ns period), rst held high then
//  dropped after #22 (so it deasserts mid-cycle, same as the original
//  directed tb), s_valid/s_last held low and m_ready held low until the
//  UVM run phase's own driver/monitor take over.
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
        .rst    (vif.rst),
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
        vif.rst     = 1'b1;
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        vif.m_ready = 1'b0;
        for (int ch = 0; ch < 4; ch++)
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++)
                    vif.s_window[ch][r][c] = '0;

        #22 vif.rst = 1'b0;

        uvm_config_db #(virtual conv2d_fsm_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
