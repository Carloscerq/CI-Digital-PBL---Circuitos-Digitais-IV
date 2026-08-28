// ---------------------------------------------------------------------
//  conv2d_fsm_agent  --  standard sequencer/driver/monitor bundle, plus
//  wiring the driver's item_ap (ground-truth window + expected m_last)
//  into the monitor's item_imp so the monitor can pair driven items with
//  observed output beats FIFO-wise. Always active, mirroring
//  mlp_agent/line_buffer_3x3_agent -- this project only needs one active
//  agent driving/observing the conv2d_fsm DUT.
// ---------------------------------------------------------------------
class conv2d_fsm_agent extends uvm_agent;

    `uvm_component_utils(conv2d_fsm_agent)

    uvm_sequencer #(conv2d_fsm_seq_item) sequencer;
    conv2d_fsm_driver                    driver;
    conv2d_fsm_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(conv2d_fsm_seq_item)::type_id::create("sequencer", this);
        driver    = conv2d_fsm_driver::type_id::create("driver", this);
        monitor   = conv2d_fsm_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
        driver.item_ap.connect(monitor.item_imp);
    endfunction

endclass
