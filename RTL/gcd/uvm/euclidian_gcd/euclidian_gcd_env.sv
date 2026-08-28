// ---------------------------------------------------------------------
//  euclidian_gcd_env  --  wires the agent's monitor into the scoreboard.
//  No cfg object is needed (same simplification as mac_env/mlp_env):
//  euclidian_gcd has no elaboration-time parameters for the scoreboard
//  to mirror, everything it needs (in_a, in_b, out) travels inside each
//  euclidian_gcd_seq_item.
// ---------------------------------------------------------------------
class euclidian_gcd_env #(
    int SIZE = 32
) extends uvm_env;

    `uvm_component_param_utils(euclidian_gcd_env #(SIZE))

    euclidian_gcd_agent #(SIZE)      agent;
    euclidian_gcd_scoreboard #(SIZE) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = euclidian_gcd_agent #(SIZE)::type_id::create("agent", this);
        scoreboard = euclidian_gcd_scoreboard #(SIZE)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
