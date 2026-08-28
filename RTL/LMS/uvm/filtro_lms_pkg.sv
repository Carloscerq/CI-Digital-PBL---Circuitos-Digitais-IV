// ---------------------------------------------------------------------
//  filtro_lms_pkg  --  all UVM classes for the filtro_lms testbench.
//  filtro_lms_if.sv is intentionally NOT included here: SystemVerilog
//  interfaces live outside packages, so it's compiled as its own
//  top-level unit (see filtro_lms_uvm.files) before this package and
//  before the module that instantiates both it and the DUT.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package filtro_lms_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // scoreboard analysis imps: one for the driver's driven-sample
    // stream, one for the monitor's independently-observed output
    // stream.
    `uvm_analysis_imp_decl(_driven)
    `uvm_analysis_imp_decl(_observed)

    `include "filtro_lms_seq_item.sv"
    `include "filtro_lms_sequences.sv"
    `include "filtro_lms_driver.sv"
    `include "filtro_lms_monitor.sv"
    `include "filtro_lms_agent.sv"
    `include "filtro_lms_scoreboard.sv"
    `include "filtro_lms_env.sv"
    `include "filtro_lms_test.sv"

endpackage
