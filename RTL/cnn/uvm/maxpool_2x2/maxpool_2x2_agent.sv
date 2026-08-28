// ---------------------------------------------------------------------
//  maxpool_2x2_agent  --  standard sequencer/driver/monitor bundle.
//  Always active, mirroring line_buffer_3x3_agent -- this project only
//  needs one active agent driving/observing the maxpool_2x2 DUT.
// ---------------------------------------------------------------------
class maxpool_2x2_agent extends uvm_agent;

    `uvm_component_utils(maxpool_2x2_agent)

    uvm_sequencer #(maxpool_2x2_seq_item) sequencer;
    maxpool_2x2_driver                    driver;
    maxpool_2x2_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(maxpool_2x2_seq_item)::type_id::create("sequencer", this);
        driver    = maxpool_2x2_driver::type_id::create("driver", this);
        monitor   = maxpool_2x2_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
