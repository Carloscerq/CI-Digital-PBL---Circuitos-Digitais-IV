// ---------------------------------------------------------------------
//  euclidian_gcd_monitor  --  independently detects the start/ready
//                              protocol on the interface (rather than
//                              reusing the driver's req item), the same
//                              split mac_monitor/mlp_monitor use: this
//                              keeps the driver purely about applying
//                              stimulus, and means the monitor's item --
//                              in_a/in_b sampled at the start edge, out
//                              sampled once ready is seen -- is exactly
//                              what the scoreboard needs.
// ---------------------------------------------------------------------
class euclidian_gcd_monitor #(
    int SIZE = 32
) extends uvm_monitor;

    `uvm_component_param_utils(euclidian_gcd_monitor #(SIZE))

    virtual euclidian_gcd_if #(SIZE) vif;
    uvm_analysis_port #(euclidian_gcd_seq_item #(SIZE)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual euclidian_gcd_if #(SIZE))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        euclidian_gcd_seq_item #(SIZE) item;

        forever begin
            @(negedge vif.clk);
            if (vif.start === 1'b1) begin
                item = euclidian_gcd_seq_item #(SIZE)::type_id::create("item");
                item.in_a = vif.in_a;
                item.in_b = vif.in_b;

                do begin
                    @(negedge vif.clk);
                end while (vif.ready !== 1'b1);

                item.out = vif.out;
                ap.write(item);
            end
        end
    endtask

endclass
