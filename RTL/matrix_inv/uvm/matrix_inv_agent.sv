// ---------------------------------------------------------------------
//  matrix_inv_agent  --  standard sequencer/driver/monitor bundle,
//  always active (same as the other agents in RTL/).
// ---------------------------------------------------------------------
class matrix_inv_agent extends uvm_agent;

    `uvm_component_utils(matrix_inv_agent)

    uvm_sequencer #(matrix_inv_seq_item) sequencer;
    matrix_inv_driver                    driver;
    matrix_inv_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(matrix_inv_seq_item)::type_id::create("sequencer", this);
        driver    = matrix_inv_driver::type_id::create("driver", this);
        monitor   = matrix_inv_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
