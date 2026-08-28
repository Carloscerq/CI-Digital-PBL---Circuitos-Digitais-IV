// ---------------------------------------------------------------------
//  filtro_lms_env  --  wires the agent's two independent analysis
//  streams (driver.ap, the driven-sample stream; monitor.ap, the
//  observed-output stream) into the scoreboard's two analysis imps, the
//  same way spi_env.sv pairs spi_driver.ap/spi_monitor.ap against
//  spi_scoreboard's expected_export/observed_export.
// ---------------------------------------------------------------------
class filtro_lms_env extends uvm_env;

    `uvm_component_utils(filtro_lms_env)

    filtro_lms_agent      agent;
    filtro_lms_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = filtro_lms_agent::type_id::create("agent", this);
        scoreboard = filtro_lms_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.ap.connect(scoreboard.driven_export);
        agent.monitor.ap.connect(scoreboard.observed_export);
    endfunction

endclass
