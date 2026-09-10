// ---------------------------------------------------------------------
//  mlp_if  --  connects the UVM agent to the mlp DUT.
//
//  Unlike perceptron_if, this DUT is clocked and stateful: the driver
//  pulses `start` for one cycle, then `features` must stay stable until
//  `done` rises (`mlp` streams the vector in over ~132 cycles). `clk`
//  here is the DUT's real clock, not just a pacing signal.
// ---------------------------------------------------------------------
interface mlp_if (
    input logic clk
);

    import mlp_weights_pkg::*;

    logic reset;
    logic start;

    logic signed [ACC_WIDTH-1:0] features [N_IN];
    logic signed [ACC_WIDTH-1:0] logits   [N_OUT];
    logic [1:0] class_idx;
    logic       busy;
    logic       done;

endinterface
