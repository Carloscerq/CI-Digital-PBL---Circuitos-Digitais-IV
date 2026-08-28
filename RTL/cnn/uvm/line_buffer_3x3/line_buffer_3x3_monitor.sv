// ---------------------------------------------------------------------
//  line_buffer_3x3_window_item  --  one observed output window: the
//  master-side data the DUT actually produced (m_window) plus whether
//  m_last was asserted alongside it. Deliberately not compared to
//  anything here -- the monitor only records what came out; the
//  scoreboard is what independently recomputes the expected window and
//  judges it.
// ---------------------------------------------------------------------
class line_buffer_3x3_window_item extends uvm_sequence_item;

    logic signed [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:2][0:2];
    bit                           last;

    `uvm_object_utils(line_buffer_3x3_window_item)

    function new(string name = "line_buffer_3x3_window_item");
        super.new(name);
    endfunction

endclass

// ---------------------------------------------------------------------
//  line_buffer_3x3_monitor  --  two jobs, both on the passive
//  (observation) side of the master interface:
//
//  (a) applies the same ~75% randomized m_ready backpressure that
//      monitor_output() in tb_line_buffer_3x3.sv does, toggled every
//      negedge before sampling whether a window is actually accepted
//      (m_valid && m_ready) -- this "monitor drives the response-side
//      ready" shape matches the original directed tb's own
//      monitor_output() task, which plays the same dual role;
//
//  (b) captures every accepted output window verbatim (no correctness
//      judgement here -- see line_buffer_3x3_scoreboard.sv, which does
//      the independent from-first-principles recomputation using the
//      frame the driver published on its own analysis port).
// ---------------------------------------------------------------------
class line_buffer_3x3_monitor extends uvm_monitor;

    `uvm_component_utils(line_buffer_3x3_monitor)

    virtual line_buffer_3x3_if vif;
    uvm_analysis_port #(line_buffer_3x3_window_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual line_buffer_3x3_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        line_buffer_3x3_window_item item;

        vif.m_ready = 1'b1;

        forever begin
            @(negedge vif.clk);
            // Randomly toggle m_ready to heavily stress the
            // backpressure/stall logic, same probability as
            // monitor_output()'s $urandom_range(0,3) != 0.
            vif.m_ready = ($urandom_range(0, 3) != 0);

            if (vif.m_valid && vif.m_ready) begin
                item = line_buffer_3x3_window_item::type_id::create("item");
                item.window = vif.m_window;
                item.last   = vif.m_last;
                ap.write(item);
            end
        end
    endtask

endclass
