// ---------------------------------------------------------------------
//  dense_layer_fsm_if  --  connects the UVM agent to the dense_layer_fsm
//  DUT: an AXI4-Stream slave side that consumes IN_FEATURES/IN_CHANNELS
//  "pixels" (IN_CHANNELS-wide beats) of one frame, and an AXI4-Stream
//  master side that emits exactly ONE beat (OUT_CLASSES logits) per
//  frame, with m_last asserted on that single beat -- frame-granularity
//  output, like RTL/mlp_model's mlp.sv (start-in/done-out), NOT
//  per-beat output like conv2d_fsm/line_buffer_3x3.
//
//  Fixed at DATA_WIDTH=24/FRAC_BITS=16/IN_CHANNELS=8/OUT_CLASSES=4/
//  IN_FEATURES=2048 -- the same configuration tb_dense_layer_fsm.sv
//  exercises and the only one this testbench targets, since (like MLP)
//  this DUT's geometry is tied to a real trained weight ROM
//  ($readmemh("mem/cnn/dense_weights.mem", ...)) rather than being
//  freely parameterizable. DATA_WIDTH and IN_CHANNELS/OUT_CLASSES are
//  duplicated here as localparams (rather than imported from
//  dense_layer_fsm_pkg) because this interface, like every interface in
//  this repo, is compiled as its own standalone unit ahead of the
//  package -- keep these in sync with dense_layer_fsm_pkg.sv by hand if
//  the geometry ever changes.
// ---------------------------------------------------------------------
interface dense_layer_fsm_if (
    input logic clk
);

    localparam int DATA_WIDTH  = 24;
    localparam int IN_CHANNELS = 8;
    localparam int OUT_CLASSES = 4;

    logic rst;

    // AXI4-Stream slave side: input pixels, one IN_CHANNELS-wide beat
    // per cycle, pixel-major/channel-minor stream order
    logic                          s_valid;
    logic                          s_ready;
    logic signed [DATA_WIDTH-1:0]  s_data [0:IN_CHANNELS-1];
    logic                          s_last;

    // AXI4-Stream master side: exactly one OUT_CLASSES-wide beat per
    // frame (the frame's logits), m_last asserted alongside it
    logic                          m_valid;
    logic                          m_ready;
    logic signed [DATA_WIDTH-1:0]  m_data [0:OUT_CLASSES-1];
    logic                          m_last;

endinterface
