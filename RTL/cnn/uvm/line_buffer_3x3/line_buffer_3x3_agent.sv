// ---------------------------------------------------------------------
//  line_buffer_3x3_agent  --  standard sequencer/driver/monitor bundle.
//  Always active, mirroring perceptron_agent/mlp_agent -- this project
//  only needs one active agent driving/observing the line_buffer_3x3
//  DUT.
// ---------------------------------------------------------------------
class line_buffer_3x3_agent extends uvm_agent;

    `uvm_component_utils(line_buffer_3x3_agent)

    uvm_sequencer #(line_buffer_3x3_seq_item) sequencer;
    line_buffer_3x3_driver                    driver;
    line_buffer_3x3_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(line_buffer_3x3_seq_item)::type_id::create("sequencer", this);
        driver    = line_buffer_3x3_driver::type_id::create("driver", this);
        monitor   = line_buffer_3x3_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
