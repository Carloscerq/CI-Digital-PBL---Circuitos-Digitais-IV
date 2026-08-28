// ---------------------------------------------------------------------
//  filtro_lms_agent  --  standard sequencer/driver/monitor bundle.
//  Always active (no passive mode).
// ---------------------------------------------------------------------
class filtro_lms_agent extends uvm_agent;

    `uvm_component_utils(filtro_lms_agent)

    uvm_sequencer #(filtro_lms_seq_item) sequencer;
    filtro_lms_driver                    driver;
    filtro_lms_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(filtro_lms_seq_item)::type_id::create("sequencer", this);
        driver    = filtro_lms_driver::type_id::create("driver", this);
        monitor   = filtro_lms_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
