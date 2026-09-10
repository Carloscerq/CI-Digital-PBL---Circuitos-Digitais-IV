// ---------------------------------------------------------------------
//  line_buffer_3x3_driver  --  streams one frame's pixels onto the
//  slave (input) AXI4-Stream side, honouring s_ready backpressure,
//  mirroring feed_image() in tb_line_buffer_3x3.sv exactly: s_valid and
//  s_data are set on the falling edge, s_last is asserted on the very
//  last pixel (r == IMG_HEIGHT-1 && c == IMG_WIDTH-1), and the driver
//  waits across full posedges for s_ready before moving to the next
//  pixel.
//
//  frame_ap publishes the whole frame (the same item just streamed) the
//  moment it starts driving, so the scoreboard can independently
//  reconstruct the zero-padded golden frame and check every output
//  window against it from first principles -- rather than the monitor
//  or scoreboard trusting anything the DUT produces. This is the same
//  "driver publishes ground truth on its own analysis port" shape used
//  in place of the DUT-trusting original tb's "check only the first
//  window" approach.
// ---------------------------------------------------------------------
class line_buffer_3x3_driver extends uvm_driver #(line_buffer_3x3_seq_item);

    `uvm_component_utils(line_buffer_3x3_driver)

    virtual line_buffer_3x3_if vif;
    uvm_analysis_port #(line_buffer_3x3_seq_item) frame_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        frame_ap = new("frame_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual line_buffer_3x3_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  line_buffer_3x3_uvm_top.sv; it belongs here because the driver is
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
        phase.raise_objection(this, "line_buffer_3x3: applying reset");

        vif.reset   = 1'b1;
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) vif.s_data[ch] = '0;

        repeat (RESET_CYCLES) @(posedge vif.clk);
        // Deassert on a negedge so reset never changes on the same edge
        // the DUT's synchronous reset samples.
        @(negedge vif.clk);
        vif.reset = 1'b0;

        phase.drop_objection(this, "line_buffer_3x3: reset released");
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            frame_ap.write(req);   // publish ground truth before/while streaming it
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_frame(line_buffer_3x3_seq_item item);
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++) vif.s_data[ch] = '0;

        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                // 1. Inject data on the falling edge, like feed_image()
                @(negedge vif.clk);
                vif.s_valid = 1'b1;

                for (int ch = 0; ch < IN_CHANNELS; ch++)
                    vif.s_data[ch] = item.pixels[r][c][ch];

                vif.s_last = (r == IMG_HEIGHT - 1) && (c == IMG_WIDTH - 1);

                // 2. Wait for the rising edge, and keep waiting full
                //    cycles while the DUT stalls (s_ready low)
                @(posedge vif.clk);
                while (!vif.s_ready) @(posedge vif.clk);
            end
        end

        @(negedge vif.clk);
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
    endtask

endclass
