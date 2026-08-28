// ---------------------------------------------------------------------
//  preprocess_lms_fft_agent  --  standard sequencer/driver/monitor
//  bundle. Always active, mirroring smma_cnn_top_agent/mac_q8_16_agent
//  -- this testbench only needs one active agent driving/observing the
//  preprocess_lms_fft_four_modes DUT.
// ---------------------------------------------------------------------
class preprocess_lms_fft_agent extends uvm_agent;

    `uvm_component_utils(preprocess_lms_fft_agent)

    uvm_sequencer #(preprocess_lms_fft_seq_item) sequencer;
    preprocess_lms_fft_driver                    driver;
    preprocess_lms_fft_monitor                   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = uvm_sequencer #(preprocess_lms_fft_seq_item)::type_id::create("sequencer", this);
        driver    = preprocess_lms_fft_driver::type_id::create("driver", this);
        monitor   = preprocess_lms_fft_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass
