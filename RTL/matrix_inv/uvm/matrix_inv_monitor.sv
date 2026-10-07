// ---------------------------------------------------------------------
//  matrix_inv_monitor  --  rebuilds each transaction from the pins
//  alone, sampling on negedge (the driver moves signals 1ns after
//  posedge):
//    1. input frame: s_dim on the first beat (0 / > N_MAX -> N_MAX, as
//       the DUT does), every element, and where s_last was seen. The
//       frame ends at s_last or after dim*dim beats, like the DUT.
//    2. compute time: cycles with neither s_ready nor m_valid, i.e.
//       the cycles the DUT spent in its compute states.
//    3. output frame: every element, whether m_last sat on the last
//       beat only, and whether the flags held still for the whole frame.
//  One complete item is written per matrix; the scoreboard does the rest.
// ---------------------------------------------------------------------
class matrix_inv_monitor extends uvm_monitor;

    `uvm_component_utils(matrix_inv_monitor)

    virtual matrix_inv_if #(DATA_W, DIM_W) vif;
    uvm_analysis_port #(matrix_inv_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual matrix_inv_if #(DATA_W, DIM_W))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        matrix_inv_seq_item item;
        int idx, dim;
        bit sing, ovf, ferr;

        forever begin
            item = matrix_inv_seq_item::type_id::create("item");
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++) begin
                    item.a_loaded[r][c] = 0;
                    item.inv[r][c]      = 0;
                end

            // ---- input frame ----
            do @(negedge vif.clk); while (vif.reset || !(vif.s_valid && vif.s_ready));
            dim = (vif.s_dim == 0 || vif.s_dim > N_MAX) ? N_MAX : int'(vif.s_dim);
            item.obs_dim      = dim;
            item.last_seen_at = -1;
            idx = 0;
            forever begin
                if (vif.s_valid && vif.s_ready) begin
                    item.a_loaded[idx / dim][idx % dim] = int'(vif.s_data);
                    if (vif.s_last) item.last_seen_at = idx;
                    idx++;
                    if (vif.s_last || idx == dim*dim) break;
                end
                @(negedge vif.clk);
            end

            // ---- compute ----
            item.cycles = 0;
            forever begin
                @(negedge vif.clk);
                if (vif.m_valid) break;
                if (!vif.s_ready) item.cycles++;
            end

            // ---- output frame ----
            sing = vif.m_singular;
            ovf  = vif.m_overflow;
            ferr = vif.m_frame_err;
            item.singular  = sing;
            item.overflow  = ovf;
            item.frame_err = ferr;
            item.last_ok   = 1'b1;
            item.n_out     = 0;
            forever begin
                if (vif.m_singular !== sing || vif.m_overflow !== ovf || vif.m_frame_err !== ferr)
                    item.last_ok = 1'b0;
                if (vif.m_valid && vif.m_ready) begin
                    if (item.n_out < dim*dim)
                        item.inv[item.n_out / dim][item.n_out % dim] = int'(vif.m_data);
                    if (vif.m_last != (item.n_out == dim*dim - 1))
                        item.last_ok = 1'b0;
                    item.n_out++;
                    if (vif.m_last || item.n_out > dim*dim) break;
                end
                @(negedge vif.clk);
            end

            ap.write(item);
        end
    endtask

endclass
