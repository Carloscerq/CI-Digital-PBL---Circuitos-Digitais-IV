// ---------------------------------------------------------------------
//  maxpool_2x2_pkg  --  all UVM classes for the maxpool_2x2 testbench.
//  maxpool_2x2_if.sv is intentionally NOT included here: SystemVerilog
//  interfaces live outside packages, so it's compiled as its own
//  top-level unit (see the .files list) before this package and before
//  the module that instantiates both it and the DUT -- same layout
//  line_buffer_3x3_pkg.sv/mlp_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/IMG_WIDTH=32/CHANNELS=8, matching
//  tb_maxpool_2x2.sv's default instance parameters exactly (maxpool_2x2
//  has no separate height parameter -- IMG_WIDTH doubles as the square
//  frame's height, same as the DUT itself) -- this DUT's geometry is
//  tied to a real image size, so (as with line_buffer_3x3_pkg/mlp_pkg)
//  there is nothing to gain from class parameterization here.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package maxpool_2x2_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH = 24;
    parameter int IMG_WIDTH  = 32;
    parameter int CHANNELS   = 8;
    parameter int OUT_WIDTH  = IMG_WIDTH / 2;         // pooled grid is 16x16
    parameter int NUM_OUT    = OUT_WIDTH * OUT_WIDTH; // 256 pooled outputs/frame

    `include "maxpool_2x2_seq_item.sv"
    `include "maxpool_2x2_sequences.sv"
    `include "maxpool_2x2_driver.sv"
    `include "maxpool_2x2_monitor.sv"
    `include "maxpool_2x2_agent.sv"
    `include "maxpool_2x2_scoreboard.sv"
    `include "maxpool_2x2_env.sv"
    `include "maxpool_2x2_test.sv"

endpackage
