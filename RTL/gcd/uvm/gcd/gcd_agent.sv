// ---------------------------------------------------------------------
//  gcd_agent  --  standard sequencer/driver/monitor bundle. Always
//  active, mirroring mlp_agent/perceptron_agent -- this project only
//  needs an active agent for the gcd DUT.
// ---------------------------------------------------------------------
class gcd_agent #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_agent;

    `uvm_component_param_utils(gcd_agent #(AMOUNT_OF_NUMBERS, SIZE))

    uvm_sequencer #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE)) sequencer;
    gcd_driver #(AMOUNT_OF_NUMBERS, SIZE)                    driver;
    gcd_monitor #(AMOUNT_OF_NUMBERS, SIZE)                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE))::type_id::create("sequencer", this);
        driver    = gcd_driver #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("driver", this);
        monitor   = gcd_monitor #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
