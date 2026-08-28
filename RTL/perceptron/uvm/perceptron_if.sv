// ---------------------------------------------------------------------
//  perceptron_if  --  connects the UVM agent to the (combinational)
//                      perceptron DUT.
//
//  The DUT has no clock: `clk` here exists only so the driver/monitor
//  have a common edge to pace transactions on. The driver applies a new
//  `inputs` vector on posedge clk; the monitor samples `inputs`/`out` on
//  the following negedge, once the DUT's combinational logic has had a
//  full half period to settle.
// ---------------------------------------------------------------------
interface perceptron_if #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) (
    input logic clk
);

    logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS];
    logic signed [DATA_WIDTH-1:0] out;

endinterface
