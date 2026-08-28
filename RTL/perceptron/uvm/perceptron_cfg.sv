// ---------------------------------------------------------------------
//  perceptron_cfg  --  mirrors the DUT instance's elaboration-time
//                       parameters (WEIGHTS/BIAS/SCALE/Q_FRAC/RELU) so
//                       the scoreboard's golden model can match whatever
//                       perceptron configuration the top module built.
//
//  These are ordinary parameter *values*, not types, so they travel as
//  plain object fields through uvm_config_db rather than as class
//  parameters like NUM_INPUTS/DATA_WIDTH (which do have to match the
//  agent/scoreboard's class parameterization).
// ---------------------------------------------------------------------
class perceptron_cfg extends uvm_object;

    `uvm_object_utils(perceptron_cfg)

    int     num_inputs;
    int     data_width;
    int     q_frac;
    bit     relu;
    longint bias;
    longint scale;
    longint weights[];   // sized to num_inputs by whoever builds this cfg

    function new(string name = "perceptron_cfg");
        super.new(name);
    endfunction

endclass
