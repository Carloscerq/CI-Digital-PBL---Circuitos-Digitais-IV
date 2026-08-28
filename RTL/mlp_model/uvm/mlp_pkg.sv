// ---------------------------------------------------------------------
//  mlp_pkg  --  all UVM classes for the mlp testbench. mlp_if.sv is
//  intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  the .files list) before this package and before the module that
//  instantiates both it and the DUT -- same layout perceptron_pkg.sv
//  uses.
//
//  The DPI-C imports are declared here, at package scope, rather than
//  inside a module like mlp_tb_dpi.sv does: they need to be visible to
//  mlp_scoreboard.sv (`include`d below), which is the only class that
//  calls them. Signatures are copied verbatim from mlp_tb_dpi.sv so
//  they link against the same mlp_ref.cpp with no wrapper needed.
// ---------------------------------------------------------------------
package mlp_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    import mlp_weights_pkg::*;

    import "DPI-C" function void   ref_set_input(input int idx, input int val);
    import "DPI-C" function void   ref_run();
    import "DPI-C" function int    ref_get_logit(input int idx);
    import "DPI-C" function int    ref_get_class();
    import "DPI-C" function int    ref_get_saturated();
    import "DPI-C" function int    ref_get_float_class();
    import "DPI-C" function real   ref_get_float_logit(input int idx);
    import "DPI-C" function int    ref_get_scale(input int layer);

    `include "mlp_seq_item.sv"
    `include "mlp_sequences.sv"
    `include "mlp_driver.sv"
    `include "mlp_monitor.sv"
    `include "mlp_agent.sv"
    `include "mlp_scoreboard.sv"
    `include "mlp_env.sv"
    `include "mlp_test.sv"

endpackage
