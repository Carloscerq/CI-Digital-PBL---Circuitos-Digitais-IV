// ---------------------------------------------------------------------
//  cnn_top_monitor  --  entirely passive, and entirely
//  self-sufficient: it watches BOTH halves of the top-level AXI4-Stream
//  boundary directly on the interface and needs no cooperation from the
//  driver (unlike line_buffer_3x3's driver, which had to publish a
//  golden frame for its scoreboard's bit-exact reconstruction -- this
//  testbench is protocol/integration-level only, see
//  cnn_top_scoreboard.sv). Two independent, concurrent jobs:
//
//  (a) watch_input() -- counts s_axis_valid && s_axis_ready beats as
//      they're accepted, resetting the count to 0 every time an
//      accepted beat also carries s_axis_last. Each such frame's final
//      beat count is pushed onto `input_beat_queue`, a FIFO of
//      completed-frame lengths. This gives an "exactly 1024 accepted
//      input beats per frame" measurement with zero dependence on
//      anything the driver does or knows.
//
//  (b) watch_output() -- applies the same randomized ~1/3 m_axis_ready
//      backpressure monitor_top() in tb_cnn_top.sv does
//      ($urandom_range(0,2) != 0, toggled every negedge), and on every
//      accepted output beat (m_axis_valid && m_axis_ready) builds a
//      result item: the 4 named logits, m_axis_last, the
//      dense_data_probe snapshot (see cnn_top_if.sv for how that's
//      wired), and the input frame length popped off
//      input_beat_queue's front -- this is how "beats never arrive
//      early" is caught structurally: if no input frame has finished
//      yet, the queue is empty and that's flagged directly as an error
//      right here, rather than only being noticed downstream in the
//      scoreboard.
//
//      watch_output() also runs a direct stability/no-glitch check
//      while m_axis_valid is high but not yet accepted (the DUT is
//      supposed to hold the dense-layer MAC output stable in ST_OUTPUT
//      until m_ready is seen, see dense_layer_fsm.sv's "Halt MAC to
//      preserve stable output" comment) -- this is the same kind of
//      direct interface-level protocol check monitor_top() itself does
//      for m_axis_last, just extended to data stability too.
//
//  "Never missing" (an input frame completes but no output beat ever
//  follows) is checked in report_phase() below: any frame length left
//  sitting unconsumed in input_beat_queue at the end of the run means
//  its matching output never arrived.
// ---------------------------------------------------------------------
class cnn_top_monitor extends uvm_monitor;

    `uvm_component_utils(cnn_top_monitor)

    virtual cnn_top_if vif;
    uvm_analysis_port #(cnn_top_seq_item) ap;

    // FIFO of completed input-frame accepted-beat counts, produced by
    // watch_input() and consumed by watch_output() to pair each output
    // beat with the input frame that produced it.
    int unsigned input_beat_queue [$];
    int unsigned frames_completed_input;
    int unsigned early_output_errors;
    int unsigned glitch_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual cnn_top_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            watch_input();
            watch_output();
        join
    endtask

    // --- (a) slave-side accepted-beat counter, frame-length FIFO -------
    task automatic watch_input();
        int unsigned accepted;
        accepted = 0;
        forever begin
            @(posedge vif.clk);
            if (vif.reset) begin
                accepted = 0;
            end else if (vif.s_axis_valid && vif.s_axis_ready) begin
                accepted++;
                if (vif.s_axis_last) begin
                    if (accepted != NUM_PIXELS)
                        `uvm_error("BEATCOUNT",
                            $sformatf("frame %0d: s_axis_last accepted after %0d beats (expected %0d)",
                                      frames_completed_input, accepted, NUM_PIXELS))
                    input_beat_queue.push_back(accepted);
                    frames_completed_input++;
                    accepted = 0;
                end
            end
        end
    endtask

    // --- (b) master-side backpressure, capture, stability check --------
    task automatic watch_output();
        cnn_top_seq_item item;
        bit                            prev_valid;
        logic signed [DATA_WIDTH-1:0]  prev_normal, prev_unbalance, prev_misalign, prev_bearing;

        vif.m_axis_ready = 1'b1;
        prev_valid = 1'b0;

        forever begin
            @(negedge vif.clk);
            // Same ~1/3 stall probability monitor_top() applies.
            vif.m_axis_ready = ($urandom_range(0, 2) != 0);

            if (vif.m_axis_valid && prev_valid) begin
                if (vif.m_axis_data_normal    !== prev_normal    ||
                    vif.m_axis_data_unbalance !== prev_unbalance ||
                    vif.m_axis_data_misalign  !== prev_misalign  ||
                    vif.m_axis_data_bearing   !== prev_bearing) begin
                    `uvm_error("GLITCH",
                        "m_axis_data_* changed while m_axis_valid stayed high and the beat had not yet been accepted")
                    glitch_errors++;
                end
            end

            if (vif.m_axis_valid) begin
                prev_normal    = vif.m_axis_data_normal;
                prev_unbalance = vif.m_axis_data_unbalance;
                prev_misalign  = vif.m_axis_data_misalign;
                prev_bearing   = vif.m_axis_data_bearing;
                prev_valid     = 1'b1;
            end else begin
                prev_valid = 1'b0;
            end

            if (vif.m_axis_valid && vif.m_axis_ready) begin
                item = cnn_top_seq_item::type_id::create("item");
                item.logit_normal    = vif.m_axis_data_normal;
                item.logit_unbalance = vif.m_axis_data_unbalance;
                item.logit_misalign  = vif.m_axis_data_misalign;
                item.logit_bearing   = vif.m_axis_data_bearing;
                item.probe_dense     = vif.dense_data_probe;
                item.last            = vif.m_axis_last;

                if (input_beat_queue.size() > 0) begin
                    item.input_beats_accepted = input_beat_queue.pop_front();
                end else begin
                    item.input_beats_accepted = 0;
                    early_output_errors++;
                    `uvm_error("EARLY",
                        "m_axis output beat observed before any input frame finished streaming (no matching frame in the queue)")
                end

                ap.write(item);
                prev_valid = 1'b0;
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("MONITOR",
            $sformatf("frames_completed_input=%0d unmatched_input_frames=%0d early_output_errors=%0d glitch_errors=%0d",
                      frames_completed_input, input_beat_queue.size(), early_output_errors, glitch_errors), UVM_LOW)

        if (input_beat_queue.size() != 0)
            `uvm_error("MISSING",
                $sformatf("%0d input frame(s) completed streaming but never produced a matching output beat",
                          input_beat_queue.size()))
    endfunction

endclass
