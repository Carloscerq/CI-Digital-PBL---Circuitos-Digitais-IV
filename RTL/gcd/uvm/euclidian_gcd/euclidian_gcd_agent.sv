// ---------------------------------------------------------------------
//  euclidian_gcd_agent  --  standard sequencer/driver/monitor bundle.
//  Always active, mirroring mac_agent/mlp_agent -- this project only
//  needs an active agent for the euclidian_gcd DUT.
// ---------------------------------------------------------------------
class euclidian_gcd_agent #(
    int SIZE = 32
) extends uvm_agent;

    `uvm_component_param_utils(euclidian_gcd_agent #(SIZE))

    uvm_sequencer #(euclidian_gcd_seq_item #(SIZE)) sequencer;
    euclidian_gcd_driver #(SIZE)                     driver;
    euclidian_gcd_monitor #(SIZE)                    monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(euclidian_gcd_seq_item #(SIZE))::type_id::create("sequencer", this);
        driver    = euclidian_gcd_driver #(SIZE)::type_id::create("driver", this);
        monitor   = euclidian_gcd_monitor #(SIZE)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
