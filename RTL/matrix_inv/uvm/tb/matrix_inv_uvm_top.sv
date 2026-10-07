// ---------------------------------------------------------------------
//  matrix_inv_uvm_top  --  DUT + interface + UVM entry point.
//
//  The DUT is built with the parameters from matrix_inv_ref_pkg, the
//  same values the scoreboard's reference model uses, so the two cannot
//  drift apart. Reset is driven by matrix_inv_driver's reset_phase.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module matrix_inv_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import matrix_inv_ref_pkg::*;
    import matrix_inv_pkg::*;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    matrix_inv_if #(DATA_W, DIM_W) vif (.clk(clk));

    matrix_inv #(
        .N_MAX     (N_MAX),
        .DATA_W    (DATA_W),
        .FRAC_W    (FRAC_W),
        .GUARD_W   (GUARD_W),
        .INT_W     (INT_W),
        .PIVOT_EPS (PIVOT_EPS)
    ) dut (
        .clk         (vif.clk),
        .reset       (vif.reset),
        .s_valid     (vif.s_valid),
        .s_ready     (vif.s_ready),
        .s_data      (vif.s_data),
        .s_last      (vif.s_last),
        .s_dim       (vif.s_dim),
        .m_valid     (vif.m_valid),
        .m_ready     (vif.m_ready),
        .m_data      (vif.m_data),
        .m_last      (vif.m_last),
        .m_singular  (vif.m_singular),
        .m_overflow  (vif.m_overflow),
        .m_frame_err (vif.m_frame_err)
    );

    initial begin
        uvm_config_db #(virtual matrix_inv_if #(DATA_W, DIM_W))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
