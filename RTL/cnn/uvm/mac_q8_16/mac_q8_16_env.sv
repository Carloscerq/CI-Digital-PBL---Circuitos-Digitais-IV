// ---------------------------------------------------------------------
//  mac_q8_16_env  --  wires the agent's monitor into the scoreboard. No
//  cfg object is needed (mirrors RTL/mac/uvm/mac_env.sv): mac_q8_16 has
//  no elaboration-time parameters for the scoreboard to mirror,
//  everything it needs (a, b, out) travels inside each seq_item.
// ---------------------------------------------------------------------
class mac_q8_16_env #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_env;

    `uvm_component_param_utils(mac_q8_16_env #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    mac_q8_16_agent #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)      agent;
    mac_q8_16_scoreboard #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = mac_q8_16_agent #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("agent", this);
        scoreboard = mac_q8_16_scoreboard #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
