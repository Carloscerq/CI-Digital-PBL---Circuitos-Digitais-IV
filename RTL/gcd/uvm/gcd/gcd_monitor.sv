// ---------------------------------------------------------------------
//  gcd_monitor  --  independently detects the `ready` pulse on the
//                    interface (rather than reusing the driver's req
//                    item) and samples `in`/`out` once it fires. `in` is
//                    still stable at that point: the driver only changes
//                    it for the next item after the current one's
//                    item_done, which happens strictly after the ready
//                    pulse this monitor is watching for.
// ---------------------------------------------------------------------
class gcd_monitor #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_monitor;

    `uvm_component_param_utils(gcd_monitor #(AMOUNT_OF_NUMBERS, SIZE))

    virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE) vif;
    uvm_analysis_port #(gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE) item;
        forever begin
            @(posedge vif.ready);
            #1;
            item = gcd_seq_item #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("item");
            item.in  = vif.in;
            item.out = vif.out;
            ap.write(item);
        end
    endtask

endclass
