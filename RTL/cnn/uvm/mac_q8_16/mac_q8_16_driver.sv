// ---------------------------------------------------------------------
//  mac_q8_16_driver  --  drives one whole accumulation job per item, one
//  tap per negedge clk, exactly mirroring tb_mac_q8_16.sv's directed
//  tests: tap 0 asserts clr (with en), taps 1..n_taps-1 assert en only,
//  then -- because mac_q8_16 is a 3-stage pipeline (a/b register ->
//  mult_reg -> acc_reg, all gated by `en`) -- 3 more negedges of en=1,
//  a=b=0 are held after the last tap before the item is retired: the
//  first of those sets a/b back to 0 (so nothing further accumulates),
//  and it takes 2 additional posedges beyond that for the last tap's
//  product to finish draining through mult_reg into acc_reg. This is
//  exactly the negedge count every case in tb_mac_q8_16.sv uses between
//  its last tap and reading `out` (see e.g. the single-tap tests: one
//  negedge to zero a/b, then two more idle negedges before the check).
//
//  `en` is deliberately never dropped back to 0 here (unlike
//  RTL/mac/uvm/mac_driver.sv, which drops load/en together at the end of
//  a job): mac_q8_16's pipeline registers only advance while en=1, so
//  dropping en during the drain would stall the very propagation this
//  driver is waiting for.
//
//  rst is deliberately NOT touched here: reset sequencing is a
//  top/test-level concern (see tb/mac_q8_16_uvm_top.sv), and by the time
//  items start flowing through this driver rst is assumed already
//  deasserted. Note mac_q8_16's rst is SYNCHRONOUS (unlike RTL/mac's
//  async rst_n), which only matters for how the top sequences it.
// ---------------------------------------------------------------------
class mac_q8_16_driver #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_driver #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS));

    `uvm_component_param_utils(mac_q8_16_driver #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);

            for (int i = 0; i < req.n_taps; i++) begin
                @(negedge vif.clk);
                vif.a   = req.a[i];
                vif.b   = req.b[i];
                vif.clr = (i == 0);
                vif.en  = 1'b1;
            end

            // drain: last tap's product needs 2 more posedges to reach
            // acc_reg (stage2: mult_reg <= a_reg*b_reg, stage3: acc_reg
            // <= acc_reg + mult_reg), so 3 negedges must elapse after the
            // last tap's negedge before `out` is guaranteed settled.
            @(negedge vif.clk);
            vif.clr = 1'b0;
            vif.a   = '0;
            vif.b   = '0;
            @(negedge vif.clk);
            @(negedge vif.clk);

            seq_item_port.item_done();
        end
    endtask

endclass
