// ---------------------------------------------------------------------
//  gcd_pkg  --  all UVM classes for the gcd testbench. gcd_if.sv is
//  intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  the .files list) before this package and before the module that
//  instantiates both it and the DUT -- same layout mlp_pkg.sv/
//  perceptron_pkg.sv use.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package gcd_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "gcd_seq_item.sv"
    `include "gcd_sequences.sv"
    `include "gcd_driver.sv"
    `include "gcd_monitor.sv"
    `include "gcd_agent.sv"
    `include "gcd_scoreboard.sv"
    `include "gcd_env.sv"
    `include "gcd_test.sv"

endpackage
