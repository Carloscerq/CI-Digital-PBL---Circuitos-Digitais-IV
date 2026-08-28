// ---------------------------------------------------------------------
//  gcd_driver  --  drives one array-reduction per item, exactly
//                  mirroring validate_full() in gcd_tb.sv: `in` is
//                  applied, then a one-cycle `start` pulse is bracketed
//                  by two negedges, then the driver waits for the
//                  `ready` pulse (plus the same `#1` settle gcd_tb.sv
//                  uses before sampling) before completing the item.
// ---------------------------------------------------------------------
class gcd_driver #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_driver #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE));

    `uvm_component_param_utils(gcd_driver #(AMOUNT_OF_NUMBERS, SIZE))

    virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);

            @(negedge vif.clk);
            vif.in    = req.in;
            vif.start = 1'b1;
            @(negedge vif.clk) vif.start = 1'b0;

            @(posedge vif.ready);
            #1;

            seq_item_port.item_done();
        end
    endtask

endclass
