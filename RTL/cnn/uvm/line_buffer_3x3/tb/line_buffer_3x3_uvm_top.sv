// ---------------------------------------------------------------------
//  line_buffer_3x3_uvm_top  --  DUT + interface + UVM entry point for
//  the CNN's line-buffer / sliding-window generator.
//
//  Clock and reset sequencing mirror tb_line_buffer_3x3.sv exactly:
//  a free-running clk toggling every #5 (10ns period), rst held high
//  then dropped after #22 (so it deasserts mid-cycle, same as the
//  original directed tb), s_valid/s_last/s_data held at their idle
//  values and m_ready held low until the UVM run phase's own
//  driver/monitor take over.
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
        .rst     (vif.rst),
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
        vif.rst     = 1'b1;
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        vif.m_ready = 1'b0;
        for (int ch = 0; ch < 4; ch++) vif.s_data[ch] = '0;

        #22 vif.rst = 1'b0;

        uvm_config_db #(virtual line_buffer_3x3_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
