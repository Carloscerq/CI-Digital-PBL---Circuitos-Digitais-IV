// ---------------------------------------------------------------------
//  mac_q8_16_agent  --  standard sequencer/driver/monitor bundle. Always
//  active (no passive mode), matching RTL/mac/uvm/mac_agent.sv.
// ---------------------------------------------------------------------
class mac_q8_16_agent #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_agent;

    `uvm_component_param_utils(mac_q8_16_agent #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    uvm_sequencer #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)) sequencer;
    mac_q8_16_driver #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)                    driver;
    mac_q8_16_monitor #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))::type_id::create("sequencer", this);
        driver    = mac_q8_16_driver #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("driver", this);
        monitor   = mac_q8_16_monitor #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
