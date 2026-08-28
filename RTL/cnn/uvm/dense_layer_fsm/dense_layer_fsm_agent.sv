// ---------------------------------------------------------------------
//  dense_layer_fsm_agent  --  standard sequencer/driver/monitor bundle.
//  Always active, mirroring line_buffer_3x3_agent/mlp_agent -- this
//  project only needs one active agent driving/observing the
//  dense_layer_fsm DUT.
// ---------------------------------------------------------------------
class dense_layer_fsm_agent extends uvm_agent;

    `uvm_component_utils(dense_layer_fsm_agent)

    uvm_sequencer #(dense_layer_fsm_seq_item) sequencer;
    dense_layer_fsm_driver                    driver;
    dense_layer_fsm_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(dense_layer_fsm_seq_item)::type_id::create("sequencer", this);
        driver    = dense_layer_fsm_driver::type_id::create("driver", this);
        monitor   = dense_layer_fsm_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
