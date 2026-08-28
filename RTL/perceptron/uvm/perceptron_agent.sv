// ---------------------------------------------------------------------
//  perceptron_agent  --  standard sequencer/driver/monitor bundle.
//  Always active (no passive mode) since this project only needs an
//  active agent for the perceptron DUT.
// ---------------------------------------------------------------------
class perceptron_agent #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_agent;

    `uvm_component_param_utils(perceptron_agent #(NUM_INPUTS, DATA_WIDTH))

    uvm_sequencer #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH)) sequencer;
    perceptron_driver #(NUM_INPUTS, DATA_WIDTH)                    driver;
    perceptron_monitor #(NUM_INPUTS, DATA_WIDTH)                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH))::type_id::create("sequencer", this);
        driver    = perceptron_driver #(NUM_INPUTS, DATA_WIDTH)::type_id::create("driver", this);
        monitor   = perceptron_monitor #(NUM_INPUTS, DATA_WIDTH)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
