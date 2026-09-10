// ---------------------------------------------------------------------
//  cnn_top_env  --  wires the agent's monitor analysis port into
//  the scoreboard's uvm_subscriber export, same shape mlp_env uses.
// ---------------------------------------------------------------------
class cnn_top_env extends uvm_env;

    `uvm_component_utils(cnn_top_env)

    cnn_top_agent      agent;
    cnn_top_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = cnn_top_agent::type_id::create("agent", this);
        scoreboard = cnn_top_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
