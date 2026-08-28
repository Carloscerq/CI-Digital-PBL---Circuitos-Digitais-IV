// ---------------------------------------------------------------------
//  euclidian_gcd_pkg  --  all UVM classes for the euclidian_gcd
//  testbench. euclidian_gcd_if.sv is intentionally NOT included here:
//  SystemVerilog interfaces live outside packages, so it's compiled as
//  its own top-level unit (see the .files list) before this package and
//  before the module that instantiates both it and the DUT -- same
//  layout mac_pkg.sv/mlp_pkg.sv use.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package euclidian_gcd_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "euclidian_gcd_seq_item.sv"
    `include "euclidian_gcd_sequences.sv"
    `include "euclidian_gcd_driver.sv"
    `include "euclidian_gcd_monitor.sv"
    `include "euclidian_gcd_agent.sv"
    `include "euclidian_gcd_scoreboard.sv"
    `include "euclidian_gcd_env.sv"
    `include "euclidian_gcd_test.sv"

endpackage
