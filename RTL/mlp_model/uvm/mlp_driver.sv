// ---------------------------------------------------------------------
//  mlp_driver  --  drives one inference per item: sets `features`, then
//                  pulses `start` for one cycle, exactly mirroring
//                  run_dut() in mlp_tb_dpi.sv (features set, then two
//                  negedges bracket the start pulse), then waits for
//                  `done`. `features` is left untouched by anything
//                  else while the DUT is busy, so it stays stable for
//                  the whole ~132-cycle streaming window as required.
//
//  Latency measurement lives in the monitor (see mlp_monitor.sv), not
//  here: the monitor watches `start`/`done` on the interface
//  independently of the driver, so it can count cycles without any
//  extra bookkeeping threaded through the driver/sequencer handshake.
// ---------------------------------------------------------------------
class mlp_driver extends uvm_driver #(mlp_seq_item);

    `uvm_component_utils(mlp_driver)

    virtual mlp_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mlp_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);

            vif.features = req.features;      // stable well before the start pulse

            @(negedge vif.clk); vif.start = 1'b1;
            @(negedge vif.clk); vif.start = 1'b0;

            while (vif.done !== 1'b1) @(negedge vif.clk);

            seq_item_port.item_done();
        end
    endtask

endclass
