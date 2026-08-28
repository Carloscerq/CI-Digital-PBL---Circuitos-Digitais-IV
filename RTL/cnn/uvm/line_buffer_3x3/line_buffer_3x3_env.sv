// ---------------------------------------------------------------------
//  line_buffer_3x3_env  --  wires both of the agent's analysis ports
//  into the scoreboard: the driver's frame_ap (ground-truth pixel data,
//  published once per frame) and the monitor's ap (observed output
//  windows, published once per accepted window).
// ---------------------------------------------------------------------
class line_buffer_3x3_env extends uvm_env;

    `uvm_component_utils(line_buffer_3x3_env)

    line_buffer_3x3_agent      agent;
    line_buffer_3x3_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = line_buffer_3x3_agent::type_id::create("agent", this);
        scoreboard = line_buffer_3x3_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.frame_ap.connect(scoreboard.frame_export);
        agent.monitor.ap.connect(scoreboard.win_export);
    endfunction

endclass
