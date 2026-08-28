// ---------------------------------------------------------------------
//  dense_layer_fsm_pkg  --  all UVM classes for the dense_layer_fsm
//  testbench. dense_layer_fsm_if.sv is intentionally NOT included here:
//  SystemVerilog interfaces live outside packages, so it's compiled as
//  its own top-level unit (see the .files list) before this package and
//  before the module that instantiates both it and the DUT -- same
//  layout conv2d_fsm_pkg.sv/mlp_pkg.sv/line_buffer_3x3_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/FRAC_BITS=16/IN_CHANNELS=8/
//  OUT_CLASSES=4/IN_FEATURES=2048, matching dense_layer_fsm.sv's default
//  parameterization exactly (the same values tb_dense_layer_fsm.sv
//  exercises) -- this DUT's geometry is tied to its trained weight ROM
//  ($readmemh("mem/cnn/dense_weights.mem", ...)) the same way MLP's is,
//  so there is nothing to gain from class parameterization here.
//
//  NUM_PIXELS = IN_FEATURES/IN_CHANNELS = 256 is the number of
//  IN_CHANNELS-wide beats streamed per frame (see dense_layer_fsm.sv's
//  rom_addr sweep, derived in full in dense_layer_fsm_scoreboard.sv).
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package dense_layer_fsm_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH  = 24;
    parameter int FRAC_BITS   = 16;
    parameter int IN_CHANNELS = 8;
    parameter int OUT_CLASSES = 4;
    parameter int IN_FEATURES = 2048;
    parameter int NUM_PIXELS  = IN_FEATURES / IN_CHANNELS;

    `include "dense_layer_fsm_seq_item.sv"
    `include "dense_layer_fsm_sequences.sv"
    `include "dense_layer_fsm_driver.sv"
    `include "dense_layer_fsm_monitor.sv"
    `include "dense_layer_fsm_agent.sv"
    `include "dense_layer_fsm_scoreboard.sv"
    `include "dense_layer_fsm_env.sv"
    `include "dense_layer_fsm_test.sv"

endpackage
