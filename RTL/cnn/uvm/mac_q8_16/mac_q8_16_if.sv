// ---------------------------------------------------------------------
//  mac_q8_16_if  --  connects the UVM agent to the (clocked) mac_q8_16
//  DUT. Unlike RTL/mac/mac.sv, mac_q8_16.sv's reset is SYNCHRONOUS
//  (`if (rst)` inside the `always_ff @(posedge clk)` block, not an
//  async `posedge clk or negedge rst_n`), so `rst` here is active-high
//  and sampled on posedge clk like every other signal. All signals are
//  plain (non-clocking-block) logic, driven/sampled directly by the
//  driver/monitor/top on negedge clk, mirroring tb_mac_q8_16.sv's own
//  style.
// ---------------------------------------------------------------------
interface mac_q8_16_if #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16
) (
    input logic clk
);

    logic rst;
    logic en;
    logic clr;

    logic signed [DATA_WIDTH-1:0] a;
    logic signed [DATA_WIDTH-1:0] b;
    logic signed [DATA_WIDTH-1:0] out;

endinterface
