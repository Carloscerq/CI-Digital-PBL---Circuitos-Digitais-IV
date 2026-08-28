// ---------------------------------------------------------------------
//  mac_pkg  --  all UVM classes for the mac testbench. mac_if.sv is
//  intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  the .files list) before this package and before the module that
//  instantiates both it and the DUT.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package mac_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "mac_seq_item.sv"
    `include "mac_sequences.sv"
    `include "mac_driver.sv"
    `include "mac_monitor.sv"
    `include "mac_agent.sv"
    `include "mac_scoreboard.sv"
    `include "mac_env.sv"
    `include "mac_test.sv"

endpackage
