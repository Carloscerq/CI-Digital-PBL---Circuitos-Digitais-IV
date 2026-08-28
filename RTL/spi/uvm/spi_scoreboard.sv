// ---------------------------------------------------------------------
//  spi_scoreboard  --  pairs the driver's completed-item stream (the
//  *intended* master_word/slave_word/slave/hold) against the monitor's
//  independently-observed stream, in order, one-to-one -- there is no
//  pipelining, each exchange fully completes before the next one starts
//  -- and compares them field by field, exactly reproducing the
//  assertions in spi_controller_tb.sv's exchange() task:
//
//    data_out === slave_word        -> obs_master_side_word vs slave_word
//    slave_rx[slave] === master_word -> obs_slave_side_word vs master_word
//    per-slave word counters         -> obs_word_counts vs a running
//                                        expectation kept here, the same
//                                        way exchange() snapshots
//                                        words_before[] up front
//    slave_select_n behavior         -> obs_select_idle_at_end vs hold
//
//  Two uvm_analysis_imp ports (via `uvm_analysis_imp_decl, declared in
//  spi_pkg.sv) each push into their own queue; whenever both queues have
//  an entry, one is popped from each and compared.
// ---------------------------------------------------------------------
class spi_scoreboard #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_component;

    `uvm_component_param_utils(spi_scoreboard #(SIZE, N_SLAVES))

    uvm_analysis_imp_expected #(spi_seq_item #(SIZE, N_SLAVES), spi_scoreboard #(SIZE, N_SLAVES)) expected_export;
    uvm_analysis_imp_observed #(spi_seq_item #(SIZE, N_SLAVES), spi_scoreboard #(SIZE, N_SLAVES)) observed_export;

    spi_seq_item #(SIZE, N_SLAVES) expected_q [$];
    spi_seq_item #(SIZE, N_SLAVES) observed_q [$];

    int unsigned match_count    = 0;
    int unsigned mismatch_count = 0;

    // running per-slave word counters, kept the same way exchange()'s
    // words_before[] snapshot does, so the delta each item introduces can
    // be checked without the monitor having to know the item boundaries.
    int prev_counts [N_SLAVES];

    int cov_slave;
    bit cov_hold;

    covergroup xfer_cg;
        option.per_instance = 1;
        cp_slave: coverpoint cov_slave { bins slave[] = {[0:N_SLAVES-1]}; }
        cp_hold:  coverpoint cov_hold  { bins held = {1'b1}; bins not_held = {1'b0}; }
        cross cp_slave, cp_hold;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        expected_export = new("expected_export", this);
        observed_export = new("observed_export", this);
        xfer_cg = new();
        foreach (prev_counts[i]) prev_counts[i] = 0;
    endfunction

    function void write_expected(spi_seq_item #(SIZE, N_SLAVES) t);
        spi_seq_item #(SIZE, N_SLAVES) t_;
        $cast(t_, t.clone());
        expected_q.push_back(t_);
        try_compare();
    endfunction

    function void write_observed(spi_seq_item #(SIZE, N_SLAVES) t);
        spi_seq_item #(SIZE, N_SLAVES) t_;
        $cast(t_, t.clone());
        observed_q.push_back(t_);
        try_compare();
    endfunction

    function void try_compare();
        spi_seq_item #(SIZE, N_SLAVES) exp_i, obs_i;
        bit ok;

        while (expected_q.size() > 0 && observed_q.size() > 0) begin
            exp_i = expected_q.pop_front();
            obs_i = observed_q.pop_front();
            ok = 1'b1;

            if (obs_i.obs_slave !== exp_i.slave) begin
                `uvm_error("MISMATCH", $sformatf(
                    "slave addressed: expected %0d observed %0d",
                    exp_i.slave, obs_i.obs_slave))
                ok = 1'b0;
            end

            if (obs_i.obs_master_side_word !== exp_i.slave_word) begin
                `uvm_error("MISMATCH", $sformatf(
                    "slave %0d -> master: expected %02h observed %02h",
                    exp_i.slave, exp_i.slave_word, obs_i.obs_master_side_word))
                ok = 1'b0;
            end

            if (obs_i.obs_slave_side_word !== exp_i.master_word) begin
                `uvm_error("MISMATCH", $sformatf(
                    "master -> slave %0d: expected %02h observed %02h",
                    exp_i.slave, exp_i.master_word, obs_i.obs_slave_side_word))
                ok = 1'b0;
            end

            if (obs_i.obs_word_counts.size() != N_SLAVES) begin
                `uvm_error("MISMATCH", $sformatf(
                    "observed word count array sized %0d, expected %0d",
                    obs_i.obs_word_counts.size(), N_SLAVES))
                ok = 1'b0;
            end else begin
                for (int s = 0; s < N_SLAVES; s++) begin
                    int expected_count;
                    expected_count = prev_counts[s] + ((s == exp_i.slave) ? 1 : 0);
                    if (obs_i.obs_word_counts[s] !== expected_count) begin
                        `uvm_error("MISMATCH", $sformatf(
                            "slave %0d received %0d words during a transfer to %0d, expected %0d",
                            s, obs_i.obs_word_counts[s] - prev_counts[s], exp_i.slave,
                            expected_count - prev_counts[s]))
                        ok = 1'b0;
                    end
                end
                for (int s = 0; s < N_SLAVES; s++) prev_counts[s] = obs_i.obs_word_counts[s];
            end

            if (exp_i.hold) begin
                if (obs_i.obs_select_idle_at_end !== 1'b0) begin
                    `uvm_error("MISMATCH", $sformatf(
                        "select released mid transaction with slave %0d", exp_i.slave))
                    ok = 1'b0;
                end
            end else begin
                if (obs_i.obs_select_idle_at_end !== 1'b1) begin
                    `uvm_error("MISMATCH", $sformatf(
                        "slave %0d still selected after the transfer", exp_i.slave))
                    ok = 1'b0;
                end
            end

            cov_slave = exp_i.slave;
            cov_hold  = exp_i.hold;
            xfer_cg.sample();

            if (ok) begin
                match_count++;
                `uvm_info("MATCH", $sformatf("exchange with slave %0d ok | %s",
                          exp_i.slave, exp_i.convert2string()), UVM_HIGH)
            end else
                mismatch_count++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD", $sformatf(
            "matches=%0d mismatches=%0d coverage=%0.1f%%",
            match_count, mismatch_count, xfer_cg.get_coverage()), UVM_LOW)
        if (mismatch_count != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", mismatch_count))
        if (expected_q.size() != 0 || observed_q.size() != 0)
            `uvm_error("SCOREBOARD", $sformatf(
                "leftover unpaired items at end of test: expected_q=%0d observed_q=%0d",
                expected_q.size(), observed_q.size()))
    endfunction

endclass
