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
//  rst is deliberately NOT touched here: reset sequencing is a
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

    task run_phase(uvm_phase phase);
        vif.desired_valid  = 1'b0;
        vif.desired_sample = '0;
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
