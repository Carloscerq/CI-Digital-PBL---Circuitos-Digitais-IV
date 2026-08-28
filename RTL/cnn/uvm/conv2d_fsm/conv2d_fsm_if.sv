// ---------------------------------------------------------------------
//  conv2d_fsm_if  --  connects the UVM agent to the conv2d_fsm DUT.
//
//  Fixed to the DUT's default parameterization (DATA_WIDTH=24,
//  FRAC_BITS=16, CHANNELS=8, IN_CHANNELS=4), matching the values
//  conv2d_fsm.sv is instantiated with everywhere else in this repo
//  (see cnn/tb/tb_conv2d_fsm.sv and sim_cnn.do). `clk` is the DUT's
//  real clock; `rst` is the DUT's synchronous reset (see
//  conv2d_fsm.sv's `always_ff @(posedge clk) if (rst) ...`).
// ---------------------------------------------------------------------
interface conv2d_fsm_if (
    input logic clk
);

    localparam int DATA_WIDTH  = 24;
    localparam int FRAC_BITS   = 16;
    localparam int CHANNELS    = 8;
    localparam int IN_CHANNELS = 4;

    logic rst;

    // AXI4-Stream Slave Interface (from line_buffer)
    logic                         s_valid;
    logic                         s_ready;
    logic signed [DATA_WIDTH-1:0] s_window [0:IN_CHANNELS-1][0:2][0:2];
    logic                         s_last;

    // AXI4-Stream Master Interface (to maxpool)
    logic                         m_valid;
    logic                         m_ready;
    logic signed [DATA_WIDTH-1:0] m_data [0:CHANNELS-1];
    logic                         m_last;

endinterface
