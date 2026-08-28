// ---------------------------------------------------------------------
//  line_buffer_3x3_pkg  --  all UVM classes for the line_buffer_3x3
//  testbench. line_buffer_3x3_if.sv is intentionally NOT included here:
//  SystemVerilog interfaces live outside packages, so it's compiled as
//  its own top-level unit (see the .files list) before this package and
//  before the module that instantiates both it and the DUT -- same
//  layout mlp_pkg.sv/perceptron_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/IMG_WIDTH=32/IMG_HEIGHT=32/
//  IN_CHANNELS=4, matching tb_line_buffer_3x3.sv's default instance
//  parameters exactly -- this DUT's geometry is tied to a real image
//  size the same way MLP's is tied to its trained weights, so (as with
//  mlp_pkg.sv) there is nothing to gain from class parameterization
//  here.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package line_buffer_3x3_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH  = 24;
    parameter int IMG_WIDTH   = 32;
    parameter int IMG_HEIGHT  = 32;
    parameter int IN_CHANNELS = 4;
    parameter int PAD_WIDTH   = IMG_WIDTH + 2;
    parameter int PAD_HEIGHT  = IMG_HEIGHT + 2;
    parameter int NUM_PIXELS  = IMG_WIDTH * IMG_HEIGHT;

    `include "line_buffer_3x3_seq_item.sv"
    `include "line_buffer_3x3_sequences.sv"
    `include "line_buffer_3x3_driver.sv"
    `include "line_buffer_3x3_monitor.sv"
    `include "line_buffer_3x3_agent.sv"
    `include "line_buffer_3x3_scoreboard.sv"
    `include "line_buffer_3x3_env.sv"
    `include "line_buffer_3x3_test.sv"

endpackage
