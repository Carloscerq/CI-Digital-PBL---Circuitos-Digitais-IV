// ---------------------------------------------------------------------
//  spectrogram_generator_env  --  wires both of the agent's analysis
//  ports into the scoreboard: the driver's frame_ap (ground-truth
//  frame data, published once per frame) and the monitor's ap
//  (observed output words, published once per accepted word). Same
//  two-port shape line_buffer_3x3_env.sv uses.
// ---------------------------------------------------------------------
class spectrogram_generator_env extends uvm_env;

    `uvm_component_utils(spectrogram_generator_env)

    spectrogram_generator_agent      agent;
    spectrogram_generator_scoreboard scoreboard;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent      = spectrogram_generator_agent::type_id::create("agent", this);
        scoreboard = spectrogram_generator_scoreboard::type_id::create("scoreboard", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agent.driver.frame_ap.connect(scoreboard.frame_export);
        agent.monitor.ap.connect(scoreboard.word_export);
    endfunction

endclass
