// ---------------------------------------------------------------------
//  spi_monitor  --  passive: never reads the driver's item or intent,
//                    only DUT-visible pins/fabric, so it is actually
//                    checking the DUT rather than echoing the stimulus.
//
//  Three concurrent processes, all paced on negedge clk like
//  spi_controller_tb.sv's own stimulus/checks:
//
//   1. tracks each slave's own data_valid pulses, building up the same
//      slave_rx[]/slave_words[] state the directed tb keeps.
//   2. tracks slave_select_n to know which slave is currently addressed
//      (a plain "is any bit low" snapshot can't be taken once the
//      controller has already released it, so this is latched
//      continuously rather than sampled once).
//   3. on the controller's own data_valid pulse, captures its data_out,
//      then waits the same two-cycle settle margin exchange() gives
//      itself before reading back the addressed slave's received word,
//      word counts and slave_select_n, and publishes one observed item
//      via `ap`. The two-cycle wait is required: the addressed slave's
//      own data_valid pulses a little later than the controller's,
//      "it runs a few clks behind the pins" (spi_controller_tb.sv).
// ---------------------------------------------------------------------
class spi_monitor #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_monitor;

    `uvm_component_param_utils(spi_monitor #(SIZE, N_SLAVES))

    virtual spi_if #(SIZE, N_SLAVES) vif;
    uvm_analysis_port #(spi_seq_item #(SIZE, N_SLAVES)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if #(SIZE, N_SLAVES))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        int              active_slave;
        bit              has_active;
        int              word_counts [N_SLAVES];
        logic [SIZE-1:0] slave_rx    [N_SLAVES];

        foreach (word_counts[i]) word_counts[i] = 0;
        foreach (slave_rx[i])    slave_rx[i]    = '0;
        active_slave = 0;
        has_active   = 1'b0;

        wait (vif.reset_n === 1'b1);

        fork
            // 1. per-slave receive words and word counters
            forever begin
                @(negedge vif.clk);
                for (int s = 0; s < N_SLAVES; s++)
                    if (vif.slave_data_valid[s]) begin
                        slave_rx[s] = vif.slave_data_out[s];
                        word_counts[s]++;
                    end
            end

            // 2. which slave is currently selected
            forever begin
                @(negedge vif.clk);
                for (int s = 0; s < N_SLAVES; s++)
                    if (!vif.slave_select_n[s]) begin
                        active_slave = s;
                        has_active   = 1'b1;
                    end
            end

            // 3. reconstruct and publish one item per completed exchange
            forever begin
                spi_seq_item #(SIZE, N_SLAVES) item;
                int              this_slave;
                logic [SIZE-1:0] master_word;

                @(negedge vif.clk);
                if (vif.data_valid) begin
                    master_word = vif.data_out;
                    this_slave  = has_active ? active_slave : 0;

                    repeat (2) @(negedge vif.clk);

                    item = spi_seq_item #(SIZE, N_SLAVES)::type_id::create("item");
                    item.obs_slave               = this_slave;
                    item.obs_master_side_word    = master_word;
                    item.obs_slave_side_word     = slave_rx[this_slave];
                    item.obs_word_counts         = new[N_SLAVES];
                    for (int s = 0; s < N_SLAVES; s++)
                        item.obs_word_counts[s] = word_counts[s];
                    item.obs_select_idle_at_end  = &vif.slave_select_n;

                    if (item.obs_select_idle_at_end) has_active = 1'b0;

                    ap.write(item);
                end
            end
        join_none
    endtask

endclass
