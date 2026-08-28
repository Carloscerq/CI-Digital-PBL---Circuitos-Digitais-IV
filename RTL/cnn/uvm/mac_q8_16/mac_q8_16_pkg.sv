// ---------------------------------------------------------------------
//  mac_q8_16_pkg  --  all UVM classes for the mac_q8_16 testbench.
//  mac_q8_16_if.sv is intentionally NOT included here: SystemVerilog
//  interfaces live outside packages, so it's compiled as its own
//  top-level unit (see the .files list) before this package and before
//  the module that instantiates both it and the DUT.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package mac_q8_16_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "mac_q8_16_seq_item.sv"
    `include "mac_q8_16_sequences.sv"
    `include "mac_q8_16_driver.sv"
    `include "mac_q8_16_monitor.sv"
    `include "mac_q8_16_agent.sv"
    `include "mac_q8_16_scoreboard.sv"
    `include "mac_q8_16_env.sv"
    `include "mac_q8_16_test.sv"

endpackage
