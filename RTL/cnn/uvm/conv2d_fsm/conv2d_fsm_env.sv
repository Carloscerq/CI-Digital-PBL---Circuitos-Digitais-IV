// ---------------------------------------------------------------------
//  conv2d_fsm_env  --  wires the monitor's completed-item analysis port
//  (ground-truth window + real m_data, paired FIFO-wise per output beat)
//  into the scoreboard's subscriber export.
// ---------------------------------------------------------------------
class conv2d_fsm_env extends uvm_env;

    `uvm_component_utils(conv2d_fsm_env)

    conv2d_fsm_agent      agent;
    conv2d_fsm_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = conv2d_fsm_agent::type_id::create("agent", this);
        scoreboard = conv2d_fsm_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
