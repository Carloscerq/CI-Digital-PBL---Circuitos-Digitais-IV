// ---------------------------------------------------------------------
//  conv2d_fsm_monitor  --  three jobs:
//
//  (a) applies the same ~75% randomized m_ready backpressure that
//      monitor_outputs() in tb_conv2d_fsm.sv does, toggled every
//      negedge before sampling whether an output beat is actually
//      accepted (m_valid && m_ready) -- same "monitor drives the
//      response-side ready" shape used by line_buffer_3x3_monitor and
//      matching monitor_outputs()'s own dual role;
//
//  (b) receives every item the driver streams (via item_ap, written the
//      instant the driver starts driving it) into a FIFO, and pairs it
//      with the next accepted output beat -- this DUT is a strictly
//      in-order single FSM, one output per input window, so simple FIFO
//      order pairing is exact. Fills in item.data_out from m_data on
//      that beat -- item.data_out is exactly the "not randomized, filled
//      in by the monitor" field conv2d_fsm_seq_item.sv documents;
//
//  (c) checks m_last placement on that same beat: item.is_last (set by
//      the sequence on the last window of a batch) is the *expected*
//      m_last value for that window, per conv2d_fsm_seq_item.sv's own
//      documentation of the field -- so any mismatch (early, late, or
//      missing) is caught right here, beat by beat, without needing to
//      separately track batch boundaries.
//
//  No correctness judgement on the convolution math happens here -- see
//  conv2d_fsm_scoreboard.sv, which does the independent from-first-
//  principles recomputation using the real trained weights.
// ---------------------------------------------------------------------
class conv2d_fsm_monitor extends uvm_monitor;

    `uvm_component_utils(conv2d_fsm_monitor)

    virtual conv2d_fsm_if vif;
    uvm_analysis_port #(conv2d_fsm_seq_item) ap;             // completed items -> scoreboard
    uvm_analysis_imp #(conv2d_fsm_seq_item, conv2d_fsm_monitor) item_imp; // items <- driver

    conv2d_fsm_seq_item pending_q[$];
    int unsigned n_last_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap       = new("ap", this);
        item_imp = new("item_imp", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual conv2d_fsm_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    // --- driver's ground-truth item, queued for FIFO pairing -----------
    function void write(conv2d_fsm_seq_item t);
        pending_q.push_back(t);
    endfunction

    task run_phase(uvm_phase phase);
        conv2d_fsm_seq_item item;

        vif.m_ready = 1'b1;

        forever begin
            @(negedge vif.clk);
            // Randomly toggle m_ready to heavily stress the
            // backpressure/stall logic, same probability as
            // monitor_outputs()'s $urandom_range(0,3) != 0.
            vif.m_ready = ($urandom_range(0, 3) != 0);

            if (vif.m_valid && vif.m_ready) begin
                if (pending_q.size() == 0)
                    `uvm_fatal("NOITEM", "observed an output beat with no pending driven item")

                item = pending_q.pop_front();
                item.data_out = vif.m_data;

                if (vif.m_last !== item.is_last) begin
                    `uvm_error("MLAST",
                        $sformatf("m_last=%0b on this beat, expected %0b (item is_last)",
                                  vif.m_last, item.is_last))
                    n_last_errors++;
                end

                ap.write(item);
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("MONITOR", $sformatf("m_last placement errors=%0d", n_last_errors), UVM_LOW)
        if (n_last_errors != 0)
            `uvm_error("MONITOR", $sformatf("%0d m_last placement errors", n_last_errors))
    endfunction

endclass
