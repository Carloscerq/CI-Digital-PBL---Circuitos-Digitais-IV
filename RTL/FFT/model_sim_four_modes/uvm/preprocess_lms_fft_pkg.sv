// ---------------------------------------------------------------------
//  preprocess_lms_fft_pkg  --  all UVM classes for the
//  preprocess_lms_fft_four_modes top-level-integration testbench (the
//  FFT preprocessing pipeline's top module). preprocess_lms_fft_if.sv
//  is intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  preprocess_lms_fft_uvm.files) before this package and before the tb
//  top module that instantiates both it and the DUT -- same layout
//  cnn_top_pkg.sv/line_buffer_3x3_pkg.sv/mlp_pkg.sv use.
//
//  Fixed at DATA_WIDTH=24/FRAC_BITS=15/NORMALIZE=1/USE_LMS=0/
//  HOP_SIZE=8, matching preprocess_lms_fft_four_modes's own default
//  parameter values exactly (see tb/preprocess_lms_fft_uvm_top.sv).
//  This is a top-level/protocol-scope testbench, not a full
//  per-submodule UVM port -- see preprocess_lms_fft_scoreboard.sv for
//  the scope rationale.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package preprocess_lms_fft_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH = 24;
    parameter int FRAC_BITS  = 15;
    parameter int NORMALIZE  = 1;
    parameter int USE_LMS    = 0;
    parameter int HOP_SIZE   = 8;
    parameter int NUM_BINS   = 64;

    `include "preprocess_lms_fft_seq_item.sv"
    `include "preprocess_lms_fft_sequences.sv"
    `include "preprocess_lms_fft_driver.sv"
    `include "preprocess_lms_fft_monitor.sv"
    `include "preprocess_lms_fft_agent.sv"
    `include "preprocess_lms_fft_scoreboard.sv"
    `include "preprocess_lms_fft_env.sv"
    `include "preprocess_lms_fft_test.sv"

endpackage
