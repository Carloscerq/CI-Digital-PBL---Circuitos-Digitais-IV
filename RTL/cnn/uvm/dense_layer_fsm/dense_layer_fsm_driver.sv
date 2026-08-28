// ---------------------------------------------------------------------
//  dense_layer_fsm_driver  --  streams one frame's 256 pixels onto the
//  slave (input) AXI4-Stream side, honouring s_ready backpressure,
//  mirroring feed_dense() in tb_dense_layer_fsm.sv exactly: s_valid and
//  s_data are set combinationally then held across a posedge until
//  s_ready is seen, s_last is asserted on the very last pixel
//  (pixel_idx == NUM_PIXELS-1), and a randomized inter-pixel gap
//  ($urandom_range(0,3)==0 -> one extra idle posedge) is injected
//  between pixels exactly like the original tb's driver task.
//
//  frame_ap publishes the whole frame (the same item just streamed) the
//  moment it starts driving, so the scoreboard can independently
//  recompute the expected logits from the real trained weight ROM
//  without depending on anything the DUT did -- same "driver publishes
//  ground truth on its own analysis port" shape used in
//  line_buffer_3x3_driver.sv.
// ---------------------------------------------------------------------
class dense_layer_fsm_driver extends uvm_driver #(dense_layer_fsm_seq_item);

    `uvm_component_utils(dense_layer_fsm_driver)

    virtual dense_layer_fsm_if vif;
    uvm_analysis_port #(dense_layer_fsm_seq_item) frame_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        frame_ap = new("frame_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual dense_layer_fsm_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            frame_ap.write(req);   // publish ground truth before/while streaming it
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_frame(dense_layer_fsm_seq_item item);
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) vif.s_data[ch] = '0;

        @(negedge vif.clk);

        for (int p = 0; p < NUM_PIXELS; p++) begin
            vif.s_valid = 1'b1;
            vif.s_last  = (p == NUM_PIXELS - 1);

            for (int ch = 0; ch < IN_CHANNELS; ch++)
                vif.s_data[ch] = item.pixels[p][ch];

            @(posedge vif.clk);
            while (!vif.s_ready) @(posedge vif.clk);

            vif.s_valid = 1'b0;
            vif.s_last  = 1'b0;

            // Inject realistic inter-pixel latency, same probability as
            // feed_dense()'s $urandom_range(0,3) == 0.
            if ($urandom_range(0, 3) == 0)
                @(posedge vif.clk);
        end
    endtask

endclass
