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
