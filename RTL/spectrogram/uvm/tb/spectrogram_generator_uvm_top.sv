// ---------------------------------------------------------------------
//  spectrogram_generator_uvm_top  --  DUT + interface + UVM entry point
//  for the spectrogram ping-pong double buffer. Clock period and reset
//  sequencing mirror tb_spectrogram_generator.sv exactly: a free-running
//  clk toggling every #5 (10ns period), rst held high then dropped
//  after #22 (so it deasserts mid-cycle, same as the original tb),
//  s_axis_valid/s_axis_last and m_axis_ready held at their idle values
//  until the UVM run phase's own driver/monitor take over.
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
        .clk         (vif.clk),
        .rst         (vif.rst),
        .s_axis_valid(vif.s_axis_valid),
        .s_axis_ready(vif.s_axis_ready),
        .s_axis_data (vif.s_axis_data),
        .s_axis_last (vif.s_axis_last),
        .m_axis_valid(vif.m_axis_valid),
        .m_axis_ready(vif.m_axis_ready),
        .m_axis_data (vif.m_axis_data),
        .m_axis_last (vif.m_axis_last)
    );

    initial begin
        vif.rst          = 1'b1;
        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
        vif.m_axis_ready = 1'b0;

        #22 vif.rst = 1'b0;

        uvm_config_db #(virtual spectrogram_generator_if)::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
