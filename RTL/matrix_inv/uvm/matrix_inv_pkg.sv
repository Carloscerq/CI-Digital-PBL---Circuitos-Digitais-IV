// ---------------------------------------------------------------------
//  matrix_inv_pkg  --  all UVM classes for the matrix_inv testbench.
//  matrix_inv_if.sv lives outside the package (interfaces cannot go in
//  packages) and is compiled as its own unit before this one; see the
//  .files list. The reference models come from matrix_inv_ref_pkg, the
//  same package the directed matrix_inv_tb.sv checks against.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package matrix_inv_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import matrix_inv_ref_pkg::*;

    localparam int DIM_W = $clog2(N_MAX + 1);

    `include "matrix_inv_seq_item.sv"
    `include "matrix_inv_sequences.sv"
    `include "matrix_inv_driver.sv"
    `include "matrix_inv_monitor.sv"
    `include "matrix_inv_agent.sv"
    `include "matrix_inv_scoreboard.sv"
    `include "matrix_inv_env.sv"
    `include "matrix_inv_test.sv"

endpackage
