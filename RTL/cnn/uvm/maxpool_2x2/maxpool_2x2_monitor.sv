// ---------------------------------------------------------------------
//  maxpool_2x2_out_item  --  one observed pooled output: the master-side
//  data the DUT actually produced (data[CHANNELS]) plus whether m_last
//  was asserted alongside it. Deliberately not compared to anything
//  here -- the monitor only records what came out and tracks *where* in
//  raster order it landed; the scoreboard is what independently
//  recomputes the expected max-of-4 and judges it.
//
//  win_idx is this output's 0-based raster index within the pooled
//  (IMG_WIDTH/2 x IMG_WIDTH/2) output grid of the current frame, i.e.
//  which 2x2 block it corresponds to -- the monitor tracks its own
//  position counter (reset whenever the previous output carried
//  m_last) independently of anything the driver or scoreboard do, so
//  the scoreboard can map win_idx straight back to (r_out, c_out)
//  without needing the monitor to publish frame ground truth itself.
// ---------------------------------------------------------------------
class maxpool_2x2_out_item extends uvm_sequence_item;

    logic signed [DATA_WIDTH-1:0] data [0:CHANNELS-1];
    bit                           last;
    int unsigned                  win_idx;

    `uvm_object_utils(maxpool_2x2_out_item)

    function new(string name = "maxpool_2x2_out_item");
        super.new(name);
    endfunction

endclass

// ---------------------------------------------------------------------
//  maxpool_2x2_monitor  --  two jobs, both on the passive (observation)
//  side of the master interface:
//
//  (a) applies the same ~75% randomized m_ready backpressure that
//      monitor_pool() in tb_maxpool_2x2.sv does, toggled every negedge
//      before sampling whether an output is actually accepted
//      (m_valid && m_ready) -- this "monitor drives the response-side
//      ready" shape matches the original directed tb's own
//      monitor_pool() task, which plays the same dual role;
//
//  (b) captures every accepted output verbatim, tagged with its raster
//      position in the pooled output grid (see maxpool_2x2_out_item),
//      resetting that position counter to 0 right after an item with
//      m_last set is published (i.e. at the start of the next frame's
//      outputs) -- no correctness judgement here, see
//      maxpool_2x2_scoreboard.sv, which does the independent
//      from-first-principles max-of-4 recomputation using the frame the
//      driver published on its own analysis port.
// ---------------------------------------------------------------------
class maxpool_2x2_monitor extends uvm_monitor;

    `uvm_component_utils(maxpool_2x2_monitor)

    virtual maxpool_2x2_if vif;
    uvm_analysis_port #(maxpool_2x2_out_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual maxpool_2x2_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        maxpool_2x2_out_item item;
        int unsigned win_idx = 0;

        vif.m_ready = 1'b1;

        forever begin
            @(negedge vif.clk);
            // Randomly toggle m_ready to heavily stress the
            // backpressure/stall logic, same probability as
            // monitor_pool()'s $urandom_range(0,3) != 0.
            vif.m_ready = ($urandom_range(0, 3) != 0);

            if (vif.m_valid && vif.m_ready) begin
                item = maxpool_2x2_out_item::type_id::create("item");
                item.data    = vif.m_data;
                item.last    = vif.m_last;
                item.win_idx = win_idx;
                ap.write(item);

                if (vif.m_last) win_idx = 0;
                else             win_idx++;
            end
        end
    endtask

endclass
