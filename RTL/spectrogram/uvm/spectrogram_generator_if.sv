// ---------------------------------------------------------------------
//  spectrogram_generator_if  --  connects the UVM agent to
//  spectrogram_generator, a pure AXI4-Stream ping-pong double buffer:
//  one scalar-valued FFT-frame-in slave side and one scalar-valued
//  CNN-frame-out master side (a single s_axis_data/m_axis_data each --
//  no per-channel array, unlike the CNN interfaces under
//  RTL/cnn/uvm/*_if.sv).
//
//  Fixed at DATA_WIDTH=24/BINS_PER_FRAME=32/FRAMES_PER_SPECTROGRAM=32
//  (MEM_DEPTH=1024) -- the same default geometry
//  tb_spectrogram_generator.sv exercises and the only configuration
//  this testbench targets, for the same "tied to one fixed pipeline
//  shape, not worth class-parameterizing" reason cnn_top_if.sv /
//  line_buffer_3x3_if.sv give. DATA_WIDTH is duplicated here as a
//  localparam (rather than imported from spectrogram_generator_pkg)
//  because this interface, like every interface in this repo, is
//  compiled as its own standalone unit ahead of the package -- keep it
//  in sync with spectrogram_generator_pkg.sv by hand if the geometry
//  ever changes.
// ---------------------------------------------------------------------
interface spectrogram_generator_if (
    input logic clk
);

    localparam int DATA_WIDTH = 24;

    logic reset;

    // AXI4-Stream slave side: one FFT bin per cycle, s_axis_last on the
    // MEM_DEPTH-th (1024th) word of each frame.
    logic                          s_axis_valid;
    logic                          s_axis_ready;
    logic signed [DATA_WIDTH-1:0]  s_axis_data;
    logic                          s_axis_last;

    // AXI4-Stream master side: the same MEM_DEPTH words streamed back
    // out, in the same order, once the ping-pong buffer holding them
    // fills and its turn to be read comes up.
    logic                          m_axis_valid;
    logic                          m_axis_ready;
    logic signed [DATA_WIDTH-1:0]  m_axis_data;
    logic                          m_axis_last;

endinterface
