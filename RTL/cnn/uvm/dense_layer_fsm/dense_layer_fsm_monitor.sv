// ---------------------------------------------------------------------
//  dense_layer_fsm_result_item  --  the single observed output beat for
//  one frame: the master-side logits (m_data) the DUT actually produced
//  plus whether m_last was asserted alongside it. Deliberately not
//  compared to anything here -- the monitor only records what came out;
//  dense_layer_fsm_scoreboard.sv is what independently recomputes the
//  expected logits from the real trained weight ROM and judges them.
// ---------------------------------------------------------------------
class dense_layer_fsm_result_item extends uvm_sequence_item;

    logic signed [DATA_WIDTH-1:0] logits [OUT_CLASSES];
    bit                           last;

    `uvm_object_utils(dense_layer_fsm_result_item)

    function new(string name = "dense_layer_fsm_result_item");
        super.new(name);
    endfunction

endclass

// ---------------------------------------------------------------------
//  dense_layer_fsm_monitor  --  two jobs, both on the passive
//  (observation) side of the master interface:
//
//  (a) applies the same ~75% randomized m_ready backpressure that
//      monitor_dense() in tb_dense_layer_fsm.sv does, toggled every
//      negedge before sampling whether the output beat is actually
//      accepted (m_valid && m_ready) -- same "monitor drives the
//      response-side ready" shape the original directed tb's own
//      monitor_dense() task plays;
//
//  (b) captures the single accepted output beat per frame verbatim (no
//      correctness judgement here -- see dense_layer_fsm_scoreboard.sv,
//      which does the independent from-first-principles recomputation
//      using the frame the driver published on its own analysis port).
//      Since the DUT emits exactly one beat per frame (m_last always
//      set alongside it), there's no per-frame beat-counting to do
//      here -- each accepted beat published on ap is, by construction,
//      the whole result for the frame currently in flight.
// ---------------------------------------------------------------------
class dense_layer_fsm_monitor extends uvm_monitor;

    `uvm_component_utils(dense_layer_fsm_monitor)

    virtual dense_layer_fsm_if vif;
    uvm_analysis_port #(dense_layer_fsm_result_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual dense_layer_fsm_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        dense_layer_fsm_result_item item;

        vif.m_ready = 1'b1;

        forever begin
            @(negedge vif.clk);
            // Randomly toggle m_ready to stress the output-side
            // backpressure/hold logic, same probability as
            // monitor_dense()'s $urandom_range(0,3) != 0.
            vif.m_ready = ($urandom_range(0, 3) != 0);

            if (vif.m_valid && vif.m_ready) begin
                item = dense_layer_fsm_result_item::type_id::create("item");
                item.logits = vif.m_data;
                item.last   = vif.m_last;
                ap.write(item);
            end
        end
    endtask

endclass
