// ---------------------------------------------------------------------
//  matrix_inv_driver  --  drives the input stream and the output-side
//                         m_ready.
//
//  Timing: everything the driver touches changes 1ns after a posedge,
//  and the monitor samples on negedge, so every signal is stable when
//  it is read and when the DUT takes it on the next posedge.
//
//  Input side: one item = one frame of dim*dim beats (fewer if the item
//  ends it early with s_last), each preceded by 0..max_gap idle cycles.
//  The driver does not wait for the result; the next item simply waits
//  on s_ready, which stays low until the DUT has unloaded the previous
//  inverse.
//
//  Output side: a forked process holds m_ready high on ready_pct% of
//  cycles, so every output frame sees backpressure.
//
//  Reset is applied in reset_phase, as in euclidian_gcd_driver: main
//  phase (where the test starts its sequences) cannot begin until it is
//  done.
// ---------------------------------------------------------------------
class matrix_inv_driver extends uvm_driver #(matrix_inv_seq_item);

    `uvm_component_utils(matrix_inv_driver)

    virtual matrix_inv_if #(DATA_W, DIM_W) vif;

    int          max_gap   = 2;
    int unsigned ready_pct = 70;
    int unsigned n_driven  = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual matrix_inv_if #(DATA_W, DIM_W))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task reset_phase(uvm_phase phase);
        phase.raise_objection(this, "matrix_inv: applying reset");

        vif.s_valid = 1'b0;
        vif.s_data  = '0;
        vif.s_last  = 1'b0;
        vif.s_dim   = '0;
        vif.m_ready = 1'b0;
        vif.reset   = 1'b1;
        repeat (2) @(posedge vif.clk);
        #1 vif.reset = 1'b0;

        phase.drop_objection(this, "matrix_inv: reset released");
    endtask

    task run_phase(uvm_phase phase);
        fork
            forever begin
                @(posedge vif.clk);
                #1 vif.m_ready = ($urandom_range(99) < ready_pct);
            end
        join_none

        forever begin
            seq_item_port.get_next_item(req);
            drive_frame(req);
            n_driven++;
            seq_item_port.item_done();
        end
    endtask

    task drive_frame(matrix_inv_seq_item t);
        int n_beats, idx;

        n_beats = (t.last_at < t.dim*t.dim) ? t.last_at + 1 : t.dim*t.dim;

        @(posedge vif.clk);
        #1;
        idx = 0;
        for (int r = 0; r < t.dim; r++)
            for (int c = 0; c < t.dim; c++) begin
                if (idx >= n_beats) break;
                repeat ($urandom_range(max_gap)) begin
                    vif.s_valid = 1'b0;
                    @(posedge vif.clk);
                    #1;
                end
                vif.s_valid = 1'b1;
                vif.s_data  = DATA_W'(t.a[r][c]);
                vif.s_last  = (idx == t.last_at);
                vif.s_dim   = DIM_W'(t.dim_field);
                while (!vif.s_ready) begin
                    @(posedge vif.clk);
                    #1;
                end
                @(posedge vif.clk);      // beat taken on this edge
                #1;
                idx++;
            end
        vif.s_valid = 1'b0;
        vif.s_last  = 1'b0;
    endtask

endclass
