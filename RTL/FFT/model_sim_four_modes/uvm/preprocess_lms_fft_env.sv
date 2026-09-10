// ---------------------------------------------------------------------
//  preprocess_lms_fft_env  --  wires the agent's monitor analysis port
//  into the scoreboard's uvm_subscriber export, same shape
//  cnn_top_env/mlp_env use.
// ---------------------------------------------------------------------
class preprocess_lms_fft_env extends uvm_env;

    `uvm_component_utils(preprocess_lms_fft_env)

    preprocess_lms_fft_agent      agent;
    preprocess_lms_fft_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = preprocess_lms_fft_agent::type_id::create("agent", this);
        scoreboard = preprocess_lms_fft_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.monitor.ap.connect(scoreboard.analysis_export);
    endfunction

endclass
