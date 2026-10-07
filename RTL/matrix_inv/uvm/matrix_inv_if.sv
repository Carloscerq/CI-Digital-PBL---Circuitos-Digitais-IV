// ---------------------------------------------------------------------
//  matrix_inv_if  --  connects the UVM agent to the matrix_inv DUT.
//
//  `clk` is the DUT's real clock. All other signals are plain logic,
//  driven and sampled on negedge clk by the driver/monitor, the same
//  style as euclidian_gcd_if and the directed matrix_inv_tb.sv: values
//  set or read at a negedge are stable across the following posedge,
//  which is where the DUT takes them.
// ---------------------------------------------------------------------
interface matrix_inv_if #(
    int DATA_W = 24,
    int DIM_W  = 3
) (
    input logic clk
);

    logic reset;

    logic                     s_valid;
    logic                     s_ready;
    logic signed [DATA_W-1:0] s_data;
    logic                     s_last;
    logic [DIM_W-1:0]         s_dim;

    logic                     m_valid;
    logic                     m_ready;
    logic signed [DATA_W-1:0] m_data;
    logic                     m_last;
    logic                     m_singular;
    logic                     m_overflow;
    logic                     m_frame_err;

endinterface
