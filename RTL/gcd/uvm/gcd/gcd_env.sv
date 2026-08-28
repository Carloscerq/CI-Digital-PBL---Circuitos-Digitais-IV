// ---------------------------------------------------------------------
//  gcd_env  --  wires the agent's monitor into the scoreboard.
// ---------------------------------------------------------------------
class gcd_env #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_env;

    `uvm_component_param_utils(gcd_env #(AMOUNT_OF_NUMBERS, SIZE))

    gcd_agent #(AMOUNT_OF_NUMBERS, SIZE)      agent;
    gcd_scoreboard #(AMOUNT_OF_NUMBERS, SIZE) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = gcd_agent #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("agent", this);
        scoreboard = gcd_scoreboard #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
