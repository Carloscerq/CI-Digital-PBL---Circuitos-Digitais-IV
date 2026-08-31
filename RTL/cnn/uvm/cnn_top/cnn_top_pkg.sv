// ---------------------------------------------------------------------
//  cnn_top_pkg  --  all UVM classes for the cnn_top
//  top-level-integration testbench. cnn_top_if.sv is intentionally
//  NOT included here: SystemVerilog interfaces live outside packages,
//  so it's compiled as its own top-level unit (see the .files list)
//  before this package and before the module that instantiates both it
//  and the DUT -- same layout line_buffer_3x3_pkg.sv/mlp_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/FRAC_BITS=16/IMG_WIDTH=32/
//  IMG_HEIGHT=32/IN_CHANNELS=4/CHANNELS=8/OUT_CLASSES=4/IN_FEATURES=2048,
//  matching tb_cnn_top.sv's/cnn_top.sv's default instance
//  parameters exactly -- this DUT's geometry is tied to a real trained
//  model, same reason line_buffer_3x3_pkg.sv/mlp_pkg.sv give for not
//  class-parameterizing.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package cnn_top_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH  = 24;
    parameter int FRAC_BITS   = 16;
    parameter int IMG_WIDTH   = 32;
    parameter int IMG_HEIGHT  = 32;
    parameter int IN_CHANNELS = 4;
    parameter int CHANNELS    = 8;
    parameter int OUT_CLASSES = 4;
    parameter int IN_FEATURES = 2048;
    parameter int NUM_PIXELS  = IMG_WIDTH * IMG_HEIGHT;

    `include "cnn_top_seq_item.sv"
    `include "cnn_top_sequences.sv"
    `include "cnn_top_driver.sv"
    `include "cnn_top_monitor.sv"
    `include "cnn_top_agent.sv"
    `include "cnn_top_scoreboard.sv"
    `include "cnn_top_env.sv"
    `include "cnn_top_test.sv"

endpackage
