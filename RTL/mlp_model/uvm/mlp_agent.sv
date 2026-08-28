// ---------------------------------------------------------------------
//  mlp_agent  --  standard sequencer/driver/monitor bundle. Always
//  active, mirroring perceptron_agent -- this project only needs an
//  active agent for the mlp DUT.
// ---------------------------------------------------------------------
class mlp_agent extends uvm_agent;

    `uvm_component_utils(mlp_agent)

    uvm_sequencer #(mlp_seq_item) sequencer;
    mlp_driver                    driver;
    mlp_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(mlp_seq_item)::type_id::create("sequencer", this);
        driver    = mlp_driver::type_id::create("driver", this);
        monitor   = mlp_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
