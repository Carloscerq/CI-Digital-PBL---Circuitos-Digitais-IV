// ---------------------------------------------------------------------
//  perceptron_pkg  --  all UVM classes for the perceptron testbench.
//  perceptron_if.sv is intentionally NOT included here: SystemVerilog
//  interfaces live outside packages, so it's compiled as its own
//  top-level unit (see the .files list) before this package and before
//  the module that instantiates both it and the DUT.
// ---------------------------------------------------------------------
package perceptron_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "perceptron_cfg.sv"
    `include "perceptron_seq_item.sv"
    `include "perceptron_sequences.sv"
    `include "perceptron_driver.sv"
    `include "perceptron_monitor.sv"
    `include "perceptron_agent.sv"
    `include "perceptron_scoreboard.sv"
    `include "perceptron_env.sv"
    `include "perceptron_test.sv"

endpackage
