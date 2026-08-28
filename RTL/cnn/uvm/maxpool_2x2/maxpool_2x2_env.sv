// ---------------------------------------------------------------------
//  maxpool_2x2_env  --  wires both of the agent's analysis ports into
//  the scoreboard: the driver's frame_ap (ground-truth pixel data,
//  published once per frame) and the monitor's ap (observed pooled
//  outputs, published once per accepted output, tagged with raster
//  position within the pooled grid).
// ---------------------------------------------------------------------
class maxpool_2x2_env extends uvm_env;

    `uvm_component_utils(maxpool_2x2_env)

    maxpool_2x2_agent      agent;
    maxpool_2x2_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = maxpool_2x2_agent::type_id::create("agent", this);
        scoreboard = maxpool_2x2_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.frame_ap.connect(scoreboard.frame_export);
        agent.monitor.ap.connect(scoreboard.out_export);
    endfunction

endclass
