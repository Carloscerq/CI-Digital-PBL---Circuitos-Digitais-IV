// ---------------------------------------------------------------------
//  matrix_inv_env  --  wires the monitor into the scoreboard. No cfg
//  object: the DUT parameters the scoreboard needs come from
//  matrix_inv_ref_pkg, which the top also instantiates the DUT with.
// ---------------------------------------------------------------------
class matrix_inv_env extends uvm_env;

    `uvm_component_utils(matrix_inv_env)

    matrix_inv_agent      agent;
    matrix_inv_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = matrix_inv_agent::type_id::create("agent", this);
        scoreboard = matrix_inv_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
