// ---------------------------------------------------------------------
//  preprocess_lms_fft_driver  --  streams desired_sample beats
//  continuously onto the DUT's slave (input) side: desired_valid is
//  raised once and held high across the whole run (never dropped
//  between items), only desired_sample changes per accepted beat, and
//  each beat waits across full posedges for desired_ready before the
//  next one is presented -- a plain single-beat valid/ready handshake,
//  no frame boundary on this side of the DUT.
//
//  desired_ready backpressure is trivially honored here by construction
//  (the driver only retires an item, via item_done(), once
//  desired_ready&&desired_valid have both been true at a posedge -- it
//  never advances desired_sample or claims a beat was accepted without
//  that), which is the reason no separate backpressure-honoring check
//  is needed on the driver side; see preprocess_lms_fft_monitor.sv for
//  the (randomized-backpressure) checks on the OUTPUT side instead.
//
//  reset is deliberately NOT touched here: reset sequencing is a
//  top-level concern (see tb/preprocess_lms_fft_uvm_top.sv), and by the
//  time items start flowing through this driver reset is assumed
//  already deasserted, mirroring every other driver in this repo.
// ---------------------------------------------------------------------
class preprocess_lms_fft_driver extends uvm_driver #(preprocess_lms_fft_seq_item);

    `uvm_component_utils(preprocess_lms_fft_driver)

    virtual preprocess_lms_fft_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual preprocess_lms_fft_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  preprocess_lms_fft_uvm_top.sv; it belongs here because the driver is
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
        phase.raise_objection(this, "preprocess_lms_fft: applying reset");

        vif.reset          = 1'b1;
        vif.desired_valid  = 1'b0;
        vif.desired_sample = '0;

        repeat (RESET_CYCLES) @(posedge vif.clk);
        // Deassert on a negedge so reset never changes on the same edge
        // the DUT's synchronous reset samples.
        @(negedge vif.clk);
        vif.reset = 1'b0;

        phase.drop_objection(this, "preprocess_lms_fft: reset released");
    endtask

    task run_phase(uvm_phase phase);
        @(negedge vif.clk);

        forever begin
            seq_item_port.get_next_item(req);

            vif.desired_valid  = 1'b1;
            vif.desired_sample = req.desired_sample;

            @(posedge vif.clk);
            while (!vif.desired_ready) @(posedge vif.clk);

            seq_item_port.item_done();
        end
    endtask

endclass
