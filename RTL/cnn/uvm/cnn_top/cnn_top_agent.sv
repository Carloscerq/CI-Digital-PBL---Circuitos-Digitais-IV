// ---------------------------------------------------------------------
//  cnn_top_agent  --  standard sequencer/driver/monitor bundle.
//  Always active, mirroring line_buffer_3x3_agent/mlp_agent -- this
//  project only needs one active agent driving/observing the
//  cnn_top DUT.
// ---------------------------------------------------------------------
class cnn_top_agent extends uvm_agent;

    `uvm_component_utils(cnn_top_agent)

    uvm_sequencer #(cnn_top_seq_item) sequencer;
    cnn_top_driver                    driver;
    cnn_top_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(cnn_top_seq_item)::type_id::create("sequencer", this);
        driver    = cnn_top_driver::type_id::create("driver", this);
        monitor   = cnn_top_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
