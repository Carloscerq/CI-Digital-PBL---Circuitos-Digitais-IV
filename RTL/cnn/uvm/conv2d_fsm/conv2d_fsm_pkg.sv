// ---------------------------------------------------------------------
//  conv2d_fsm_pkg  --  all UVM classes for the conv2d_fsm testbench.
//  conv2d_fsm_if.sv is intentionally NOT included here: SystemVerilog
//  interfaces live outside packages, so it's compiled as its own
//  top-level unit (see the .files list) before this package and before
//  the module that instantiates both it and the DUT -- same layout
//  mlp_pkg.sv/line_buffer_3x3_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/FRAC_BITS=16/CHANNELS=8/
//  IN_CHANNELS=4, matching conv2d_fsm.sv's default parameterization
//  exactly (the same values tb_conv2d_fsm.sv and sim_cnn.do use) -- this
//  DUT's geometry is tied to its trained weights the same way MLP's is,
//  so there is nothing to gain from class parameterization here.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package conv2d_fsm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH  = 24;
    parameter int FRAC_BITS   = 16;
    parameter int CHANNELS    = 8;
    parameter int IN_CHANNELS = 4;

    `include "conv2d_fsm_seq_item.sv"
    `include "conv2d_fsm_sequences.sv"
    `include "conv2d_fsm_driver.sv"
    `include "conv2d_fsm_monitor.sv"
    `include "conv2d_fsm_agent.sv"
    `include "conv2d_fsm_scoreboard.sv"
    `include "conv2d_fsm_env.sv"
    `include "conv2d_fsm_test.sv"

endpackage
