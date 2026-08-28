// ---------------------------------------------------------------------
//  spi_pkg  --  all UVM classes for the SPI testbench. spi_if.sv is
//  intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  the .files list) before this package and before the module that
//  instantiates it and the DUTs (tb/spi_uvm_top.sv).
// ---------------------------------------------------------------------
package spi_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // scoreboard analysis imps: one for the driver's intent stream, one
    // for the monitor's independently-observed stream.
    `uvm_analysis_imp_decl(_expected)
    `uvm_analysis_imp_decl(_observed)

    `include "spi_seq_item.sv"
    `include "spi_sequences.sv"
    `include "spi_driver.sv"
    `include "spi_monitor.sv"
    `include "spi_agent.sv"
    `include "spi_scoreboard.sv"
    `include "spi_env.sv"
    `include "spi_test.sv"

endpackage
