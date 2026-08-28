// ---------------------------------------------------------------------
//  perceptron_driver  --  applies each item's `inputs` vector on
//                          posedge clk. The DUT is combinational, so
//                          `out` is left for the monitor to sample once
//                          the logic has settled (see perceptron_if.sv).
// ---------------------------------------------------------------------
class perceptron_driver #(
    int NUM_INPUTS = 40,
    int DATA_WIDTH = 24
) extends uvm_driver #(perceptron_seq_item #(NUM_INPUTS, DATA_WIDTH));

    `uvm_component_param_utils(perceptron_driver #(NUM_INPUTS, DATA_WIDTH))

    virtual perceptron_if #(NUM_INPUTS, DATA_WIDTH) vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual perceptron_if #(NUM_INPUTS, DATA_WIDTH))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            @(posedge vif.clk);
            vif.inputs = req.inputs;
            seq_item_port.item_done();
        end
    endtask

endclass
