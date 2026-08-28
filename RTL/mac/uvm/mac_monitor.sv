// ---------------------------------------------------------------------
//  mac_monitor  --  unlike perceptron's monitor, which just samples a
//  settled combinational output on one fixed edge, the mac DUT is a
//  stateful accumulator: one "item" here is a whole load..en..en dot-
//  product job spanning many clock edges. Rather than coupling to the
//  driver, this monitor independently reconstructs job boundaries from
//  the load/en handshake itself -- a job starts the negedge `load` is
//  seen high and ends at the next idle negedge with load==0 && en==0,
//  which is exactly the trailing negedge mac_driver.sv (and mac_tb.sv's
//  run_dot task) inserts after the last tap. `vif.acc` is already
//  settled at that idle negedge (only one posedge has elapsed since the
//  last active tap was driven), so it can be sampled directly.
// ---------------------------------------------------------------------
class mac_monitor #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_monitor;

    `uvm_component_param_utils(mac_monitor #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH) vif;
    uvm_analysis_port #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        bit in_job = 1'b0;
        logic signed [DATA_WIDTH-1:0]   data_q   [$];
        logic signed [WEIGHT_WIDTH-1:0] weight_q [$];
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) item;

        forever begin
            @(negedge vif.clk);
            if (vif.load || vif.en) begin
                if (vif.load) begin
                    data_q.delete();
                    weight_q.delete();
                end
                data_q.push_back(vif.data);
                weight_q.push_back(vif.weight);
                in_job = 1'b1;
            end else if (in_job) begin
                item = mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("item");
                item.n_taps = data_q.size();
                item.data   = data_q;
                item.weight = weight_q;
                item.acc    = vif.acc;
                ap.write(item);
                in_job = 1'b0;
            end
        end
    endtask

endclass
