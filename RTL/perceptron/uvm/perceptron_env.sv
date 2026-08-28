// ---------------------------------------------------------------------
//  perceptron_env  --  wires the agent's monitor into the scoreboard.
// ---------------------------------------------------------------------
class perceptron_env #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_env;

    `uvm_component_param_utils(perceptron_env #(NUM_INPUTS, DATA_WIDTH))

    perceptron_agent #(NUM_INPUTS, DATA_WIDTH)      agent;
    perceptron_scoreboard #(NUM_INPUTS, DATA_WIDTH) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = perceptron_agent #(NUM_INPUTS, DATA_WIDTH)::type_id::create("agent", this);
        scoreboard = perceptron_scoreboard #(NUM_INPUTS, DATA_WIDTH)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
