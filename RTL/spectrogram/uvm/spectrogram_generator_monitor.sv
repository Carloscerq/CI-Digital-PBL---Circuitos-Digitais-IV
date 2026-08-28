// ---------------------------------------------------------------------
//  spectrogram_generator_monitor  --  entirely passive: it only watches
//  the master (CNN-out) AXI4-Stream side and drives m_axis_ready itself
//  (the DUT's read side has no other consumer in this testbench).
//  Applies the same ~66% random backpressure monitor_cnn_frames() in
//  tb_spectrogram_generator.sv does ($urandom_range(0,2)!=0, toggled
//  every negedge), and publishes one spectrogram_generator_word_item
//  per accepted output word (m_axis_valid && m_axis_ready), in arrival
//  order, carrying the data value and whether m_axis_last was set.
//  Needs no cooperation from the driver -- all frame-boundary/count
//  bookkeeping is done downstream in
//  spectrogram_generator_scoreboard.sv, which pairs these words up
//  against the driver's ground-truth frame queue.
// ---------------------------------------------------------------------
class spectrogram_generator_monitor extends uvm_monitor;

    `uvm_component_utils(spectrogram_generator_monitor)

    virtual spectrogram_generator_if vif;
    uvm_analysis_port #(spectrogram_generator_word_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spectrogram_generator_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        spectrogram_generator_word_item item;

        vif.m_axis_ready = 1'b0;

        forever begin
            @(negedge vif.clk);
            // ~66% ready to simulate CNN backpressure, mirroring
            // monitor_cnn_frames()'s $urandom_range(0,2)!=0.
            vif.m_axis_ready = ($urandom_range(0, 2) != 0);

            if (vif.m_axis_valid && vif.m_axis_ready) begin
                item = spectrogram_generator_word_item::type_id::create("item");
                item.data = vif.m_axis_data;
                item.last = vif.m_axis_last;
                ap.write(item);
            end
        end
    endtask

endclass
