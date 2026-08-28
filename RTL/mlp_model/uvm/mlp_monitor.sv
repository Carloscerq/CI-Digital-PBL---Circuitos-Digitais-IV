// ---------------------------------------------------------------------
//  mlp_monitor  --  independently detects the `start`/`done` protocol
//                    on the interface (rather than reusing the driver's
//                    req item) and measures latency itself, the same
//                    way run_dut() in mlp_tb_dpi.sv counts cycles: cyc
//                    is set to 1 on the negedge where `start` is
//                    sampled high, then incremented on every following
//                    negedge until `done` is sampled high.
//
//                    This split keeps the driver purely about applying
//                    stimulus (mirrors perceptron_driver/perceptron_monitor)
//                    and means the monitor's item -- features sampled at
//                    the start edge, logits/class_idx sampled once done
//                    is seen, plus the measured latency -- is exactly
//                    what the scoreboard needs, built the same way
//                    regardless of what the driver does internally.
// ---------------------------------------------------------------------
class mlp_monitor extends uvm_monitor;

    `uvm_component_utils(mlp_monitor)

    virtual mlp_if vif;
    uvm_analysis_port #(mlp_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mlp_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        mlp_seq_item item;
        int cyc;

        forever begin
            @(negedge vif.clk);
            if (vif.start === 1'b1) begin
                item = mlp_seq_item::type_id::create("item");
                item.features = vif.features;

                cyc = 1;
                while (vif.done !== 1'b1) begin
                    @(negedge vif.clk);
                    cyc++;
                end

                item.logits         = vif.logits;
                item.class_idx      = vif.class_idx;
                item.latency_cycles = cyc;
                ap.write(item);
            end
        end
    endtask

endclass
