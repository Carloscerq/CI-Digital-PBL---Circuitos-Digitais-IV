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
