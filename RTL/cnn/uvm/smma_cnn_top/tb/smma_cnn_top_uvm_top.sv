// ---------------------------------------------------------------------
//  smma_cnn_top_uvm_top  --  DUT + interface + UVM entry point for the
//  CNN's full 4-stage top-level pipeline (line_buffer_3x3 -> conv2d_fsm
//  -> maxpool_2x2 -> dense_layer_fsm).
//
//  Clock and reset sequencing mirror tb_smma_cnn_top.sv exactly: a
//  free-running clk toggling every #5 (10ns period), reset held high then
//  dropped after #22 (so it deasserts mid-cycle, same as the original
//  tb), s_axis_valid/s_axis_last/s_axis_data and m_axis_ready held at
//  their idle values until the UVM run phase's own driver/monitor take
//  over.
//
//  There's exactly one valid geometry here (see smma_cnn_top_pkg.sv),
//  so no elaboration-time cfg object is needed -- unlike perceptron's
//  testbench, nothing about the DUT instance varies from run to run.
//
//  dense_data_probe wiring: smma_cnn_top_scoreboard.sv needs to verify
//  that the 4 named output ports (m_axis_data_normal/unbalance/
//  misalign/bearing) are really wired to dense_data[0..3] in the right
//  order inside smma_cnn_top.sv, not just that they hold *some* stable
//  value -- a real, cheap check, since that breakout is literally 4
//  wire assigns in the DUT and nothing upstream would catch a swapped
//  index. Two ways to get that visibility from class-based UVM code
//  were considered:
//    (1) `bind` a small probe module/interface into the DUT's scope;
//    (2) a plain hierarchical reference from this (new) top module into
//        the DUT instance's internal signal, dut.dense_data.
//  (2) was used: `dense_data` is an ordinary internal array declared
//  directly in smma_cnn_top's own module body (not inside a generate
//  block or a submodule), so a plain hierarchical read of dut.dense_data
//  is legal SystemVerilog with no special access needed beyond the
//  -access +rwc this testbench already runs with. It needs no extra
//  bind module and is a single always_comb assignment (rather than a
//  continuous `assign`, to sidestep any tool-specific doubt about
//  continuous-assigning whole unpacked arrays -- always_comb assigning
//  an unpacked array wholesale is unambiguously supported, the same
//  pattern seq_item do_copy() functions across this repo already use
//  procedurally). Neither this file nor the probe signal ever WRITES
//  into the DUT -- only reads dense_data -- so smma_cnn_top.sv itself is
//  untouched.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module smma_cnn_top_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import smma_cnn_top_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    smma_cnn_top_if vif (.clk(clk));

    smma_cnn_top #(
        .DATA_WIDTH  (24),
        .FRAC_BITS   (16),
        .IMG_WIDTH   (32),
        .IMG_HEIGHT  (32),
        .IN_CHANNELS (4),
        .CHANNELS    (8),
        .OUT_CLASSES (4),
        .IN_FEATURES (2048)
    ) dut (
        .clk                   (vif.clk),
        .reset                   (vif.reset),
        .s_axis_valid          (vif.s_axis_valid),
        .s_axis_ready          (vif.s_axis_ready),
        .s_axis_data           (vif.s_axis_data),
        .s_axis_last           (vif.s_axis_last),
        .m_axis_valid          (vif.m_axis_valid),
        .m_axis_ready          (vif.m_axis_ready),
        .m_axis_data_normal    (vif.m_axis_data_normal),
        .m_axis_data_unbalance (vif.m_axis_data_unbalance),
        .m_axis_data_misalign  (vif.m_axis_data_misalign),
        .m_axis_data_bearing   (vif.m_axis_data_bearing),
        .m_axis_last           (vif.m_axis_last)
    );

    // See the file header above: a read-only hierarchical probe into the
    // DUT's internal dense_data signal, for the port-breakout check.
    always_comb vif.dense_data_probe = dut.dense_data;

    initial begin
        vif.reset          = 1'b1;
        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
        vif.m_axis_ready = 1'b0;
        for (int ch = 0; ch < 4; ch++) vif.s_axis_data[ch] = '0;

        #22 vif.reset = 1'b0;

        uvm_config_db #(virtual smma_cnn_top_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
