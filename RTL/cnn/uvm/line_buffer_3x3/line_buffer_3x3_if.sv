// ---------------------------------------------------------------------
//  line_buffer_3x3_if  --  connects the UVM agent to the line_buffer_3x3
//  DUT: a genuine dual AXI4-Stream pair (pixel-in slave side, window-out
//  master side), unlike the single request/response handshakes the other
//  testbenches in this repo drive (perceptron, mlp, ...).
//
//  Fixed at DATA_WIDTH=24/IMG_WIDTH=32/IMG_HEIGHT=32/IN_CHANNELS=4 -- the
//  same geometry tb_line_buffer_3x3.sv exercises, and the only
//  configuration this testbench targets (see line_buffer_3x3_pkg.sv for
//  why no class parameterization is used: this DUT's geometry is tied to
//  a fixed real image size, same simplification the MLP testbench uses
//  since MLP's geometry is tied to its trained weights). DATA_WIDTH and
//  IN_CHANNELS are duplicated here as localparams (rather than imported
//  from line_buffer_3x3_pkg) because this interface, like every
//  interface in this repo, is compiled as its own standalone unit ahead
//  of the package -- keep these in sync with line_buffer_3x3_pkg.sv by
//  hand if the geometry ever changes.
// ---------------------------------------------------------------------
interface line_buffer_3x3_if (
    input logic clk
);

    localparam int DATA_WIDTH  = 24;
    localparam int IN_CHANNELS = 4;

    logic reset;

    // AXI4-Stream slave side: input pixels, one per cycle, raster order
    logic                          s_valid;
    logic                          s_ready;
    logic signed [DATA_WIDTH-1:0]  s_data [0:IN_CHANNELS-1];
    logic                          s_last;

    // AXI4-Stream master side: output 3x3xIN_CHANNELS sliding windows,
    // one per real (unpadded) input pixel, in raster order
    logic                          m_valid;
    logic                          m_ready;
    logic signed [DATA_WIDTH-1:0]  m_window [0:IN_CHANNELS-1][0:2][0:2];
    logic                          m_last;

endinterface
