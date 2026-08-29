// ---------------------------------------------------------------------
//  conv2d_fsm_driver  --  streams windows onto the slave (input)
//  AXI4-Stream side, honouring s_ready backpressure, mirroring
//  feed_windows() in tb_conv2d_fsm.sv exactly: s_valid/s_window/s_last
//  are set, then the driver waits across full posedges for s_ready
//  before moving on, deasserts s_valid/s_last, and -- exactly like
//  feed_windows()'s `$urandom_range(0,2)==0 ? repeat(2)@(posedge clk)`
//  -- randomly inserts a 2-cycle idle gap between windows about 1/3 of
//  the time, so both gapped operation and the FSM's ST_OUTPUT-overlap-
//  with-next-ST_FEED path (s_ready asserted while m_valid is still
//  being drained) get exercised back to back.
//
//  item_ap publishes each item (the same handle just driven) the moment
//  it starts driving, so the monitor can pair it FIFO-wise with the
//  matching output beat once the DUT emits it -- this DUT is a strictly
//  in-order single FSM/pipeline, one output per input window, so FIFO
//  order always matches. This is the same "driver publishes ground
//  truth on its own analysis port" shape used by
//  line_buffer_3x3_driver's frame_ap, just emitting per-item instead of
//  per-frame.
// ---------------------------------------------------------------------
class conv2d_fsm_driver extends uvm_driver #(conv2d_fsm_seq_item);

    `uvm_component_utils(conv2d_fsm_driver)

    virtual conv2d_fsm_if vif;
    uvm_analysis_port #(conv2d_fsm_seq_item) item_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_ap = new("item_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual conv2d_fsm_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  conv2d_fsm_uvm_top.sv; it belongs here because the driver is
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
        phase.raise_objection(this, "conv2d_fsm: applying reset");

        vif.reset   = 1'b1;
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
        for (int ch = 0; ch < IN_CHANNELS; ch++)
            for (int r = 0; r < 3; r++)
                for (int c = 0; c < 3; c++)
                    vif.s_window[ch][r][c] = '0;

        repeat (RESET_CYCLES) @(posedge vif.clk);
        // Deassert on a negedge so reset never changes on the same edge
        // the DUT's synchronous reset samples.
        @(negedge vif.clk);
        vif.reset = 1'b0;

        phase.drop_objection(this, "conv2d_fsm: reset released");
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            item_ap.write(req);   // publish ground truth before/while streaming it
            drive_item(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_item(conv2d_fsm_seq_item item);
        vif.s_valid  = 1'b1;
        vif.s_last   = item.is_last;
        vif.s_window = item.window;

        @(posedge vif.clk);
        while (!vif.s_ready) @(posedge vif.clk);

        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;

        // Randomized idle gap between windows, same probability and
        // shape as feed_windows()'s own gap.
        if ($urandom_range(0, 2) == 0) begin
            repeat (2) @(posedge vif.clk);
        end
    endtask

endclass
