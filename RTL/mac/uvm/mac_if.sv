// ---------------------------------------------------------------------
//  mac_if  --  connects the UVM agent to the (clocked) mac DUT.
//
//  Unlike perceptron_if.sv, `clk` here is the DUT's real clock, not just
//  a pacing signal: mac.sv is a synchronous accumulator that latches on
//  posedge clk and resets asynchronously on rst_n. All other signals are
//  plain (non-clocking-block) logic, driven/sampled directly by the
//  driver/monitor/top on negedge clk, mirroring mac_tb.sv's own style.
// ---------------------------------------------------------------------
interface mac_if #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40
) (
    input logic clk
);

    logic rst_n;
    logic load;
    logic en;

    logic signed [DATA_WIDTH-1:0]   data;
    logic signed [WEIGHT_WIDTH-1:0] weight;
    logic signed [SUM_WIDTH-1:0]    acc;

endinterface
