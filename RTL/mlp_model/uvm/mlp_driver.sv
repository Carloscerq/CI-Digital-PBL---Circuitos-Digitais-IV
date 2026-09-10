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

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  mlp_uvm_top.sv; it belongs here because the driver is
    //  the component that holds the vif and drives the DUT's inputs.
    //  Raising an objection across the whole phase is what makes the
    //  schedule really wait for reset to finish, which in turn is what
    //  lets the bench's test class start its sequences from main_phase
    //  with no chance of stimulus overlapping reset -- run_phase spans
    //  the entire run-time schedule, so it would have overlapped it.
    // ------------------------------------------------------------------
    // Reset across four negedges then two idle cycles, exactly the
    // sequence the top module's `initial` block used to apply.
    localparam int RESET_CYCLES = 4;
    localparam int POST_RESET_IDLE_CYCLES = 2;

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "mlp: applying reset");

        vif.reset = 1'b1;
        vif.start = 1'b0;

        repeat (RESET_CYCLES) @(negedge vif.clk);
        vif.reset = 1'b0;
        repeat (POST_RESET_IDLE_CYCLES) @(negedge vif.clk);

        phase.drop_objection(this, "mlp: reset released");
    endtask

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
