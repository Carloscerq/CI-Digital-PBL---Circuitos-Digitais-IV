// ---------------------------------------------------------------------
//  maxpool_2x2_if  --  connects the UVM agent to the maxpool_2x2 DUT:
//  a single AXI4-Stream pair, pixel-in slave side (one CHANNELS-wide
//  pixel per cycle, raster order) and pooled-pixel-out master side (one
//  CHANNELS-wide output per non-overlapping 2x2 block, stride 2), same
//  handshake shape as line_buffer_3x3_if but a single s_data/m_data pair
//  instead of a window.
//
//  Fixed at DATA_WIDTH=24/IMG_WIDTH=32/CHANNELS=8 -- the same geometry
//  tb_maxpool_2x2.sv exercises (maxpool_2x2 has no separate height
//  parameter; IMG_WIDTH doubles as the square frame's height), and the
//  only configuration this testbench targets (see maxpool_2x2_pkg.sv
//  for why no class parameterization is used). DATA_WIDTH and CHANNELS
//  are duplicated here as localparams (rather than imported from
//  maxpool_2x2_pkg) because this interface, like every interface in
//  this repo, is compiled as its own standalone unit ahead of the
//  package -- keep these in sync with maxpool_2x2_pkg.sv by hand if the
//  geometry ever changes.
// ---------------------------------------------------------------------
interface maxpool_2x2_if (
    input logic clk
);

    localparam int DATA_WIDTH = 24;
    localparam int CHANNELS   = 8;

    logic reset;

    // AXI4-Stream slave side: input pixels, one per cycle, raster order
    logic                          s_valid;
    logic                          s_ready;
    logic signed [DATA_WIDTH-1:0]  s_data [0:CHANNELS-1];
    logic                          s_last;

    // AXI4-Stream master side: one pooled pixel per 2x2 block, in
    // raster order over the pooled (IMG_WIDTH/2 x IMG_WIDTH/2) grid
    logic                          m_valid;
    logic                          m_ready;
    logic signed [DATA_WIDTH-1:0]  m_data [0:CHANNELS-1];
    logic                          m_last;

endinterface
