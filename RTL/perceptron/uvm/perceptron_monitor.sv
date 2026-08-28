// ---------------------------------------------------------------------
//  perceptron_monitor  --  samples `inputs`/`out` on negedge clk (half
//                           a period after the driver applies a new
//                           vector on posedge, so the DUT's comb logic
//                           has settled) and broadcasts the pair.
// ---------------------------------------------------------------------
class perceptron_monitor #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_monitor;

    `uvm_component_param_utils(perceptron_monitor #(NUM_INPUTS, DATA_WIDTH))

    virtual perceptron_if #(NUM_INPUTS, DATA_WIDTH) vif;
    uvm_analysis_port #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual perceptron_if #(NUM_INPUTS, DATA_WIDTH))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH) item;
        forever begin
            @(negedge vif.clk);
            item = perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH)::type_id::create("item");
            item.inputs = vif.inputs;
            item.out    = vif.out;
            ap.write(item);
        end
    endtask

endclass
