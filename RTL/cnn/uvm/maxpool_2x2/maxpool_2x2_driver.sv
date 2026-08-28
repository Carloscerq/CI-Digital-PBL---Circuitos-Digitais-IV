// ---------------------------------------------------------------------
//  maxpool_2x2_driver  --  streams one frame's pixels onto the slave
//  (input) AXI4-Stream side, honouring s_ready backpressure, mirroring
//  feed_pool() in tb_maxpool_2x2.sv exactly: s_valid and s_data are set
//  on the falling edge, s_last is asserted on the very last pixel
//  (r == IMG_WIDTH-1 && c == IMG_WIDTH-1), and the driver waits across
//  full posedges for s_ready before moving to the next pixel.
//
//  frame_ap publishes the whole frame (the same item just streamed) the
//  moment it starts driving, so the scoreboard can independently
//  recompute each 2x2 block's true max (a real max of 4 values, not the
//  monotonic-pattern shortcut tb_maxpool_2x2.sv's monitor_pool() uses)
//  and check every output against it from first principles -- same
//  "driver publishes ground truth on its own analysis port" shape used
//  by line_buffer_3x3_driver.
// ---------------------------------------------------------------------
class maxpool_2x2_driver extends uvm_driver #(maxpool_2x2_seq_item);

    `uvm_component_utils(maxpool_2x2_driver)

    virtual maxpool_2x2_if vif;
    uvm_analysis_port #(maxpool_2x2_seq_item) frame_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        frame_ap = new("frame_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual maxpool_2x2_if)::get(this, "", "vif", vif))
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

    task automatic drive_frame(maxpool_2x2_seq_item item);
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        for (int ch = 0; ch < CHANNELS; ch++) vif.s_data[ch] = '0;

        for (int r = 0; r < IMG_WIDTH; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                // 1. Inject data on the falling edge, like feed_pool()
                @(negedge vif.clk);
                vif.s_valid = 1'b1;

                for (int ch = 0; ch < CHANNELS; ch++)
                    vif.s_data[ch] = item.pixels[r][c][ch];

                vif.s_last = (r == IMG_WIDTH - 1) && (c == IMG_WIDTH - 1);

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
