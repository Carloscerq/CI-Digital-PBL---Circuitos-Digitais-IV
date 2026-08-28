// ---------------------------------------------------------------------
//  mac_env  --  wires the agent's monitor into the scoreboard. No cfg
//  object is needed (unlike perceptron_env.sv): mac has no elaboration-
//  time weight/bias/scale parameters, everything the scoreboard needs
//  (data, weight, acc) travels inside each mac_seq_item.
// ---------------------------------------------------------------------
class mac_env #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_env;

    `uvm_component_param_utils(mac_env #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    mac_agent #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)      agent;
    mac_scoreboard #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = mac_agent #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("agent", this);
        scoreboard = mac_scoreboard #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
