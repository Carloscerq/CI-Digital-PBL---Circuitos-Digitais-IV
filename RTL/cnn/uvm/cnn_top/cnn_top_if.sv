// ---------------------------------------------------------------------
//  cnn_top_if  --  connects the UVM agent to cnn_top, the
//  CNN's full 4-stage pipeline (line_buffer_3x3 -> conv2d_fsm ->
//  maxpool_2x2 -> dense_layer_fsm). A genuine AXI4-Stream pair: pixel-in
//  slave side (one pixel/cycle, raster order, 1024 beats/frame) and a
//  logit-out master side (exactly ONE beat per whole frame, carrying
//  the 4 named dense-layer logits broken out as separate ports).
//
//  Fixed at DATA_WIDTH=24/FRAC_BITS=16/IMG_WIDTH=32/IMG_HEIGHT=32/
//  IN_CHANNELS=4/CHANNELS=8/OUT_CLASSES=4/IN_FEATURES=2048 -- the same
//  default geometry tb_cnn_top.sv exercises, and the only
//  configuration this testbench targets, for the same reason
//  line_buffer_3x3_if/mlp_if fix their geometry: it's tied to a real
//  trained/fixed-size model, not something worth class-parameterizing.
//  DATA_WIDTH/IN_CHANNELS/OUT_CLASSES are duplicated here as localparams
//  (rather than imported from cnn_top_pkg) because this interface,
//  like every interface in this repo, is compiled as its own
//  standalone unit ahead of the package -- keep these in sync with
//  cnn_top_pkg.sv by hand if the geometry ever changes.
// ---------------------------------------------------------------------
interface cnn_top_if (
    input logic clk
);

    localparam int DATA_WIDTH  = 24;
    localparam int IN_CHANNELS = 4;
    localparam int OUT_CLASSES = 4;

    logic reset;

    // AXI4-Stream slave side: input pixels, one per cycle, raster order,
    // IMG_WIDTH*IMG_HEIGHT (1024) beats per frame, s_axis_last on the
    // very last one.
    logic                          s_axis_valid;
    logic                          s_axis_ready;
    logic signed [DATA_WIDTH-1:0]  s_axis_data [0:IN_CHANNELS-1];
    logic                          s_axis_last;

    // AXI4-Stream master side: exactly one beat per input frame, carrying
    // the 4 dense-layer logits broken out into named scalar ports.
    logic                          m_axis_valid;
    logic                          m_axis_ready;
    logic signed [DATA_WIDTH-1:0]  m_axis_data_normal;
    logic signed [DATA_WIDTH-1:0]  m_axis_data_unbalance;
    logic signed [DATA_WIDTH-1:0]  m_axis_data_misalign;
    logic signed [DATA_WIDTH-1:0]  m_axis_data_bearing;
    logic                          m_axis_last;

    // Internal-signal probe -- NOT a DUT port. cnn_top_uvm_top.sv
    // (a new file; the DUT itself is never touched) drives this from a
    // plain hierarchical reference into the DUT instance,
    // dut.dense_data, via `always_comb`. That gives the monitor/
    // scoreboard direct visibility of the dense layer's raw m_data
    // output BEFORE the 4-way port breakout
    // (assign m_axis_data_normal = dense_data[0]; etc., in
    // cnn_top.sv), so the scoreboard can verify the breakout wiring
    // itself is correct -- i.e. that m_axis_data_unbalance really is
    // dense_data[1] and not, say, dense_data[2] with an index swapped --
    // rather than only checking that the 4 output ports hold *some*
    // stable value. See cnn_top_scoreboard.sv for the check and
    // cnn_top_uvm_top.sv for why this hierarchical-reference
    // approach was chosen over a `bind`.
    logic signed [DATA_WIDTH-1:0]  dense_data_probe [0:OUT_CLASSES-1];

endinterface
