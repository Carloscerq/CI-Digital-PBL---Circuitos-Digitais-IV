// ---------------------------------------------------------------------
//  spectrogram_generator_pkg  --  all UVM classes for the
//  spectrogram_generator testbench. spectrogram_generator_if.sv is
//  intentionally NOT included here: SystemVerilog interfaces live
//  outside packages, so it's compiled as its own top-level unit (see
//  the .files list) before this package and before the module that
//  instantiates both it and the DUT -- same layout
//  smma_cnn_top_pkg.sv/mac_pkg.sv use.
//
//  Geometry is fixed at DATA_WIDTH=24/BINS_PER_FRAME=32/
//  FRAMES_PER_SPECTROGRAM=32 (MEM_DEPTH=1024), matching
//  tb_spectrogram_generator.sv's/spectrogram_generator.sv's default
//  instance parameters exactly -- not worth class-parameterizing, same
//  reasoning smma_cnn_top_pkg.sv/line_buffer_3x3_pkg.sv give.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

package spectrogram_generator_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    parameter int DATA_WIDTH             = 24;
    parameter int BINS_PER_FRAME         = 32;
    parameter int FRAMES_PER_SPECTROGRAM = 32;
    parameter int MEM_DEPTH              = BINS_PER_FRAME * FRAMES_PER_SPECTROGRAM;

    // One whole frame's worth of golden words, used both as
    // spectrogram_generator_seq_item's `words` field type and as the
    // element type of spectrogram_generator_scoreboard.sv's FIFO of
    // driven frames.
    typedef logic signed [DATA_WIDTH-1:0] spectrogram_word_arr_t [MEM_DEPTH];

    `include "spectrogram_generator_seq_item.sv"
    `include "spectrogram_generator_sequences.sv"
    `include "spectrogram_generator_driver.sv"
    `include "spectrogram_generator_monitor.sv"
    `include "spectrogram_generator_agent.sv"
    `include "spectrogram_generator_scoreboard.sv"
    `include "spectrogram_generator_env.sv"
    `include "spectrogram_generator_test.sv"

endpackage
