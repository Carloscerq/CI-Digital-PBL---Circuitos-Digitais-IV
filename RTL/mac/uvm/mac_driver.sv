// ---------------------------------------------------------------------
//  mac_driver  --  drives one whole dot-product job per item, one tap
//                   per negedge clk, exactly mirroring mac_tb.sv's
//                   run_dot task: tap 0 asserts load, taps 1..n_taps-1
//                   assert en, then one trailing negedge drops both back
//                   to 0 before the item is retired. Stimulus changes on
//                   negedge (not posedge) because the DUT latches on
//                   posedge -- driving on negedge leaves a full half
//                   period of margin and avoids any race with the DUT's
//                   own posedge sampling.
//
//  reset is deliberately NOT touched here: reset sequencing is a
//  top/test-level concern (see tb/mac_uvm_top.sv and mac_protocol_test),
//  and by the time items start flowing through this driver reset is
//  assumed already deasserted.
// ---------------------------------------------------------------------
class mac_driver #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_driver #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS));

    `uvm_component_param_utils(mac_driver #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  mac_uvm_top.sv; it belongs here because the driver is
    //  the component that holds the vif and drives the DUT's inputs.
    //  Raising an objection across the whole phase is what makes the
    //  schedule really wait for reset to finish, which in turn is what
    //  lets the test
    //  (mac_wide_random_test / mac_protocol_test)
    //  start its sequences from main_phase with no chance of stimulus
    //  overlapping reset -- run_phase spans the entire run-time
    //  schedule, so it would have overlapped it.
    // ------------------------------------------------------------------
    // Reset across two negedges then one settled idle cycle, exactly the
    // sequence the top module's `initial` block used to apply.
    localparam int RESET_CYCLES = 2;

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "mac: applying reset");

        vif.reset  = 1'b1;
        vif.load   = 1'b0;
        vif.en     = 1'b0;
        vif.data   = '0;
        vif.weight = '0;

        repeat (RESET_CYCLES) @(negedge vif.clk);
        vif.reset = 1'b0;
        @(negedge vif.clk);

        phase.drop_objection(this, "mac: reset released");
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);

            for (int i = 0; i < req.n_taps; i++) begin
                @(negedge vif.clk);
                vif.data   = req.data[i];
                vif.weight = req.weight[i];
                vif.load   = (i == 0);
                vif.en     = 1'b1;
            end
            // one more negedge: the posedge in between latched the final tap
            @(negedge vif.clk);
            vif.load = 1'b0;
            vif.en   = 1'b0;

            seq_item_port.item_done();
        end
    endtask

endclass
