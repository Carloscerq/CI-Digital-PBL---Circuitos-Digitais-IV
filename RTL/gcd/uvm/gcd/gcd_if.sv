// ---------------------------------------------------------------------
//  gcd_if  --  connects the UVM agent to the array-reducing gcd DUT.
//
//  Like mlp_if, this DUT is clocked and stateful: the driver pulses
//  `start` for one cycle while `in` is held stable, then waits for the
//  `ready` pulse (gcd folds the array by repeatedly calling an internal
//  euclidian_gcd, one pairwise call per LOAD/CALC round trip). `clk`
//  here is the DUT's real clock, and `reset` is its synchronous
//  active-high reset -- same names/polarity as gcd.sv's ports.
// ---------------------------------------------------------------------
interface gcd_if #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) (
    input logic clk
);

    logic reset;
    logic start;

    logic [SIZE-1:0] in [AMOUNT_OF_NUMBERS];
    logic [SIZE-1:0] out;
    logic ready;

endinterface
