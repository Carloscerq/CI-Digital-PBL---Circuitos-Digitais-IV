// ---------------------------------------------------------------------
//  maxpool_2x2_uvm_top  --  DUT + interface + UVM entry point for the
//  CNN's 2x2 max-pooling unit.
//
//  Clock and reset sequencing mirror tb_maxpool_2x2.sv exactly: a
//  free-running clk toggling every #5 (10ns period), rst held high then
//  dropped after #22 (so it deasserts mid-cycle, same as the original
//  directed tb), s_valid/s_last/s_data held at their idle values and
//  m_ready held low until the UVM run phase's own driver/monitor take
//  over.
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
        .rst     (vif.rst),
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
        vif.rst     = 1'b1;
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        vif.m_ready = 1'b0;
        for (int ch = 0; ch < 8; ch++) vif.s_data[ch] = '0;

        #22 vif.rst = 1'b0;

        uvm_config_db #(virtual maxpool_2x2_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
