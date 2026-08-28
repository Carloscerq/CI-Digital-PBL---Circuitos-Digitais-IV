// ---------------------------------------------------------------------
//  dense_layer_fsm_env  --  wires both of the agent's analysis ports
//  into the scoreboard: the driver's frame_ap (ground-truth pixel data,
//  published once per frame) and the monitor's ap (the single observed
//  output beat, published once per accepted frame result).
// ---------------------------------------------------------------------
class dense_layer_fsm_env extends uvm_env;

    `uvm_component_utils(dense_layer_fsm_env)

    dense_layer_fsm_agent      agent;
    dense_layer_fsm_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = dense_layer_fsm_agent::type_id::create("agent", this);
        scoreboard = dense_layer_fsm_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.frame_ap.connect(scoreboard.frame_export);
        agent.monitor.ap.connect(scoreboard.result_export);
    endfunction

endclass
