// ---------------------------------------------------------------------
//  spectrogram_generator_agent  --  standard sequencer/driver/monitor
//  bundle. Always active, mirroring mac_agent/cnn_top_agent --
//  this testbench only needs one active agent driving/observing the
//  spectrogram_generator DUT.
// ---------------------------------------------------------------------
class spectrogram_generator_agent extends uvm_agent;

    `uvm_component_utils(spectrogram_generator_agent)

    uvm_sequencer #(spectrogram_generator_seq_item) sequencer;
    spectrogram_generator_driver                    driver;
    spectrogram_generator_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(spectrogram_generator_seq_item)::type_id::create("sequencer", this);
        driver    = spectrogram_generator_driver::type_id::create("driver", this);
        monitor   = spectrogram_generator_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
