// ---------------------------------------------------------------------
//  mac_agent  --  standard sequencer/driver/monitor bundle. Always
//  active (no passive mode), matching perceptron_agent.sv.
// ---------------------------------------------------------------------
class mac_agent #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_agent;

    `uvm_component_param_utils(mac_agent #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    uvm_sequencer #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)) sequencer;
    mac_driver #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)                    driver;
    mac_monitor #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))::type_id::create("sequencer", this);
        driver    = mac_driver #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("driver", this);
        monitor   = mac_monitor #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
