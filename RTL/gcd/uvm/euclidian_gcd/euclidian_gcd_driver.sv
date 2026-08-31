// ---------------------------------------------------------------------
//  euclidian_gcd_driver  --  drives one pairwise GCD job per item,
//                             exactly mirroring validate()'s protocol in
//                             euclidian_gcd_tb.sv: operands are set, then
//                             two negedges bracket the start pulse, then
//                             the driver waits for the posedge of ready
//                             (plus the same trailing #1 validate() uses
//                             before moving on).
//
//  reset is deliberately NOT touched here: reset sequencing is a
//  top-level concern (see tb/euclidian_gcd_uvm_top.sv), and by the time
//  items start flowing through this driver reset is assumed already
//  deasserted.
// ---------------------------------------------------------------------
class euclidian_gcd_driver #(
    int SIZE = 32
) extends uvm_driver #(euclidian_gcd_seq_item #(SIZE));

    `uvm_component_param_utils(euclidian_gcd_driver #(SIZE))

    virtual euclidian_gcd_if #(SIZE) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual euclidian_gcd_if #(SIZE))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    // ------------------------------------------------------------------
    //  reset_phase -- the UVM run-time phase that owns reset. This used
    //  to be sequenced from an `initial` block in
    //  euclidian_gcd_uvm_top.sv; it belongs here because the driver is
    //  the component that holds the vif and drives the DUT's inputs.
    //  Raising an objection across the whole phase is what makes the
    //  schedule really wait for reset to finish, which in turn is what
    //  lets the bench's test class start its sequences from main_phase
    //  with no chance of stimulus overlapping reset -- run_phase spans
    //  the entire run-time schedule, so it would have overlapped it.
    // ------------------------------------------------------------------
    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "euclidian_gcd: applying reset");

        // Same one-cycle, negedge-aligned reset pulse the top module's
        // `initial` block used to apply: the DUT starts out of reset,
        // gets pulsed for exactly one clock, then runs.
        vif.start = 1'b0;
        vif.in_a  = '0;
        vif.in_b  = '0;
        vif.reset = 1'b0;

        @(negedge vif.clk) vif.reset = 1'b1;
        @(negedge vif.clk) vif.reset = 1'b0;

        phase.drop_objection(this, "euclidian_gcd: reset released");
    endtask

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);

            @(negedge vif.clk);
            vif.in_a  = req.in_a;
            vif.in_b  = req.in_b;
            vif.start = 1'b1;
            @(negedge vif.clk) vif.start = 1'b0;
            @(posedge vif.ready);
            #1;

            seq_item_port.item_done();
        end
    endtask

endclass
