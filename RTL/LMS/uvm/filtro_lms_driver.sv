// ---------------------------------------------------------------------
//  filtro_lms_driver  --  single-beat ready/valid handshake, matching
//  tb_filtro_lms.v's own stimulus style exactly: wait for in_ready, drive
//  fft_re/fft_im + in_valid on one negedge, deassert in_valid on the
//  next negedge. `in_ready` is only ever asserted while the DUT is IDLE,
//  so there is no need to reason about the 11-state FSM latency here --
//  waiting for in_ready before every sample is sufficient.
//
//  Each driven item is published (in order, immediately after driving
//  it) on this driver's own analysis port `ap`, independent of whether
//  the DUT will ever produce a corresponding output -- the scoreboard's
//  shadow reference model needs to see every accepted sample, including
//  the very first one (which never produces output), to keep its
//  (w, x_prev, primeira_amostra) state in lockstep with the DUT. See
//  filtro_lms_scoreboard.sv.
// ---------------------------------------------------------------------
class filtro_lms_driver extends uvm_driver #(filtro_lms_seq_item);

    `uvm_component_utils(filtro_lms_driver)

    virtual filtro_lms_if vif;
    uvm_analysis_port #(filtro_lms_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual filtro_lms_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  filtro_lms_uvm_top.sv; it belongs here because the driver is
    //  the component that holds the vif and drives the DUT's inputs.
    //  Raising an objection across the whole phase is what makes the
    //  schedule really wait for reset to finish, which in turn is what
    //  lets the bench's test class start its sequences from main_phase
    //  with no chance of stimulus overlapping reset -- run_phase spans
    //  the entire run-time schedule, so it would have overlapped it.
    // ------------------------------------------------------------------
    // Three posedges of reset then two idle cycles before stimulus --
    // exactly what the old `#30 reset=0; #20;` sequence gave at this
    // bench's 10ns clock period.
    localparam int RESET_CYCLES = 3;
    localparam int POST_RESET_IDLE_CYCLES = 2;

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "filtro_lms: applying reset");

        vif.reset    = 1'b1;
        vif.in_valid = 1'b0;
        vif.fft_re   = '0;
        vif.fft_im   = '0;

        repeat (RESET_CYCLES) @(posedge vif.clk);
        // Deassert on a negedge so reset never changes on the same edge
        // the DUT's synchronous reset samples.
        @(negedge vif.clk);
        vif.reset = 1'b0;
        repeat (POST_RESET_IDLE_CYCLES) @(negedge vif.clk);

        phase.drop_objection(this, "filtro_lms: reset released");
    endtask

    task run_phase(uvm_phase phase);
        filtro_lms_seq_item rsp;

        forever begin
            seq_item_port.get_next_item(req);

            wait (vif.in_ready === 1'b1);
            @(negedge vif.clk);
            vif.fft_re   = req.fft_re;
            vif.fft_im   = req.fft_im;
            vif.in_valid = 1'b1;
            @(negedge vif.clk);
            vif.in_valid = 1'b0;

            rsp = filtro_lms_seq_item::type_id::create("rsp");
            rsp.copy(req);
            ap.write(rsp);

            seq_item_port.item_done();
        end
    endtask

endclass
