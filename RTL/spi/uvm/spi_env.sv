// ---------------------------------------------------------------------
//  spi_env  --  wires the agent's two analysis streams (driver.ap, the
//  intent; monitor.ap, the observation) into the scoreboard's two
//  independent analysis imps. The DUTs themselves (spi_controller plus
//  N_SLAVES spi_slave instances) live in the top module, not here: they
//  are plain modules, not uvm_components, and spi_controller_tb.sv's
//  topology is reproduced in tb/spi_uvm_top.sv.
// ---------------------------------------------------------------------
class spi_env #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_env;

    `uvm_component_param_utils(spi_env #(SIZE, N_SLAVES))

    spi_agent #(SIZE, N_SLAVES)      agent;
    spi_scoreboard #(SIZE, N_SLAVES) scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = spi_agent #(SIZE, N_SLAVES)::type_id::create("agent", this);
        scoreboard = spi_scoreboard #(SIZE, N_SLAVES)::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.ap.connect(scoreboard.expected_export);
        agent.monitor.ap.connect(scoreboard.observed_export);
    endfunction

endclass
