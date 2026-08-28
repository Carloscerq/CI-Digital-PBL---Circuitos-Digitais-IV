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
