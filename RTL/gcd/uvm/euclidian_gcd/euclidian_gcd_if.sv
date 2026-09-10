// ---------------------------------------------------------------------
//  euclidian_gcd_if  --  connects the UVM agent to the (clocked)
//  euclidian_gcd DUT.
//
//  Like mac_if.sv, `clk` here is the DUT's real clock, not just a pacing
//  signal: euclidian_gcd.sv is a synchronous subtraction-based (binary/
//  Euclidean) pairwise GCD that latches on posedge clk and takes its
//  active-high reset there too. All other signals are plain (non-clocking-
//  block) logic, driven/sampled directly by the driver/monitor/top on
//  negedge clk, mirroring euclidian_gcd_tb.sv's own style.
// ---------------------------------------------------------------------
interface euclidian_gcd_if #(
    int SIZE = 32
) (
    input logic clk
);

    logic reset;
    logic start;

    logic [SIZE-1:0] in_a;
    logic [SIZE-1:0] in_b;
    logic [SIZE-1:0] out;
    logic             ready;

endinterface
