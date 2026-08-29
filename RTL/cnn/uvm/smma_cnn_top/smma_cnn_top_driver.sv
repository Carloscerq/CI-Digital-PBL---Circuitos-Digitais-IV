// ---------------------------------------------------------------------
//  smma_cnn_top_driver  --  streams one frame's 1024 pixels onto the
//  top-level slave (input) AXI4-Stream side, honouring s_axis_ready
//  backpressure, mirroring feed_top() in tb_smma_cnn_top.sv exactly:
//  after one initial negedge, each pixel's s_axis_valid/s_axis_data/
//  s_axis_last are set, the driver waits for a posedge, and then keeps
//  waiting full posedges while the DUT stalls (s_axis_ready low) --
//  s_axis_last is asserted on the very last pixel (r==IMG_HEIGHT-1 &&
//  c==IMG_WIDTH-1, i.e. i==1023 in the original tb's flat indexing).
//
//  Also owns the UVM run-time reset_phase -- see the comment on
//  reset_phase() below.
//
//  Deliberately does NOT wait for the frame's output beat before
//  returning item_done(): dense_layer_fsm only re-asserts s_ready in
//  ST_IDLE, which it only re-enters once ST_OUTPUT's beat has been
//  consumed (m_ready accepted) -- so the DUT itself back-pressures a
//  new frame's pixels via the ready chain if the previous frame's
//  logits haven't been read out yet. No extra driver-side
//  synchronization is needed for that; the monitor independently
//  verifies both sides of the protocol (see smma_cnn_top_monitor.sv).
// ---------------------------------------------------------------------
class smma_cnn_top_driver extends uvm_driver #(smma_cnn_top_seq_item);

    `uvm_component_utils(smma_cnn_top_driver)

    virtual smma_cnn_top_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual smma_cnn_top_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  smma_cnn_top_uvm_top.sv; it belongs here because the driver is
    //  the component that holds the vif and drives the DUT's inputs.
    //  Raising an objection across the whole phase is what makes the
    //  schedule really wait for reset to finish, which in turn is what
    //  lets the bench's test class start its sequences from main_phase
    //  with no chance of stimulus overlapping reset -- run_phase spans
    //  the entire run-time schedule, so it would have overlapped it.
    // ------------------------------------------------------------------
    // Two posedges of reset, the same two the old `#22` hand-sequenced
    // reset covered at this bench's 10ns clock period.
    localparam int RESET_CYCLES = 2;

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "smma_cnn_top: applying reset");

        vif.reset        = 1'b1;
        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) vif.s_axis_data[ch] = '0;

        repeat (RESET_CYCLES) @(posedge vif.clk);
        // Deassert on a negedge so reset never changes on the same edge
        // the DUT's synchronous reset samples.
        @(negedge vif.clk);
        vif.reset = 1'b0;

        phase.drop_objection(this, "smma_cnn_top: reset released");
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_frame(smma_cnn_top_seq_item item);
        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) vif.s_axis_data[ch] = '0;
        @(negedge vif.clk);

        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                vif.s_axis_valid = 1'b1;

                for (int ch = 0; ch < IN_CHANNELS; ch++)
                    vif.s_axis_data[ch] = item.pixels[r][c][ch];

                vif.s_axis_last = (r == IMG_HEIGHT - 1) && (c == IMG_WIDTH - 1);

                @(posedge vif.clk);
                while (!vif.s_axis_ready) @(posedge vif.clk);
            end
        end

        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
    endtask

endclass
