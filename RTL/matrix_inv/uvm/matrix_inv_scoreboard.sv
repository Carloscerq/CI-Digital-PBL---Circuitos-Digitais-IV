// ---------------------------------------------------------------------
//  matrix_inv_scoreboard  --  two checks per matrix:
//
//  1. Bit-exact, against matrix_inv_ref_pkg::ref_inv() run on exactly
//     what the monitor saw go in: every inverse element, m_singular,
//     m_overflow, m_frame_err (expected when s_last was not on beat
//     dim*dim-1), the number of output beats, m_last only on the last
//     one, flags constant over the frame, and the compute cycle count.
//     Any difference is a UVM_ERROR.
//
//  2. Precision, against real_inv() in double precision, for every
//     result that is neither singular nor overflowed. The error in
//     Q9.15 LSBs is accumulated for the report. For strictly
//     diagonally dominant inputs (well conditioned by construction) an
//     error above PREC_TOL_LSB is also a UVM_ERROR; for the rest the
//     error depends on conditioning, so it is only reported.
//
//  The covergroup records which sizes, flags and pivot situations the
//  run actually reached.
// ---------------------------------------------------------------------
class matrix_inv_scoreboard extends uvm_subscriber #(matrix_inv_seq_item);

    `uvm_component_utils(matrix_inv_scoreboard)

    localparam real PREC_TOL_LSB = 2.0;

    int unsigned n_checked   = 0;
    int unsigned n_mismatch  = 0;
    int unsigned n_prec      = 0;
    real         max_err_dd  = 0.0;   // diagonally dominant only
    real         max_err_all = 0.0;
    real         sum_err_dd  = 0.0;
    int unsigned n_err_dd    = 0;
    int          cyc_dim[N_MAX+1];

    int cv_dim;
    bit cv_singular, cv_overflow, cv_frame_err, cv_swap;

    covergroup result_cg;
        option.per_instance = 1;
        cp_dim:       coverpoint cv_dim { bins d[] = {[1:N_MAX]}; }
        cp_singular:  coverpoint cv_singular;
        cp_overflow:  coverpoint cv_overflow;
        cp_frame_err: coverpoint cv_frame_err;
        cp_swap:      coverpoint cv_swap;
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        result_cg = new();
    endfunction

    function automatic bit diag_dominant(input int dim, input mat_t a);
        longint off;
        for (int r = 0; r < dim; r++) begin
            off = 0;
            for (int c = 0; c < dim; c++)
                if (c != r) off += (a[r][c] < 0) ? -a[r][c] : a[r][c];
            if (((a[r][r] < 0) ? -a[r][r] : a[r][r]) <= off) return 0;
        end
        return 1;
    endfunction

    function void mismatch(input string msg, matrix_inv_seq_item t);
        n_mismatch++;
        `uvm_error("MISMATCH", {msg, " | ", t.convert2string()})
    endfunction

    function void write(matrix_inv_seq_item t);
        mat_t  exp_inv;
        bit    e_sing, e_ovf, e_ferr;
        int    e_cyc, n;
        rmat_t ra, rinv;
        bit    rsing, dd;
        real   err;

        n = t.obs_dim;
        ref_inv(n, t.a_loaded, exp_inv, e_sing, e_ovf, e_cyc);
        e_ferr = (t.last_seen_at != n*n - 1);
        n_checked++;
        cyc_dim[n] = t.cycles;

        // ---------------- bit-exact ----------------
        if (t.n_out != n*n)
            mismatch($sformatf("%0d output beats, expected %0d", t.n_out, n*n), t);
        if (!t.last_ok)
            mismatch("m_last misplaced or flags changed mid-frame", t);
        if (t.singular != e_sing || t.overflow != e_ovf || t.frame_err != e_ferr)
            mismatch($sformatf("singular/overflow/frame_err = %0b%0b%0b, expected %0b%0b%0b",
                               t.singular, t.overflow, t.frame_err, e_sing, e_ovf, e_ferr), t);
        if (t.cycles != e_cyc)
            mismatch($sformatf("%0d compute cycles, expected %0d", t.cycles, e_cyc), t);
        for (int r = 0; r < n; r++)
            for (int c = 0; c < n; c++)
                if (t.inv[r][c] != exp_inv[r][c])
                    mismatch($sformatf("inv[%0d][%0d] = %0d, expected %0d",
                                       r, c, t.inv[r][c], exp_inv[r][c]), t);

        // ---------------- precision ----------------
        if (!e_sing && !e_ovf) begin
            to_real_mat(t.a_loaded, ra);
            real_inv(n, ra, rinv, rsing);
            dd = diag_dominant(n, t.a_loaded);
            n_prec++;
            for (int r = 0; r < n; r++)
                for (int c = 0; c < n; c++) begin
                    err = from_q(t.inv[r][c]) - rinv[r][c];
                    err = ((err < 0) ? -err : err) / LSB;
                    if (err > max_err_all) max_err_all = err;
                    if (dd) begin
                        sum_err_dd += err;
                        n_err_dd++;
                        if (err > max_err_dd) max_err_dd = err;
                        if (err > PREC_TOL_LSB)
                            mismatch($sformatf("inv[%0d][%0d] is %f LSB from the exact inverse",
                                               r, c, err), t);
                    end
                end
        end

        `uvm_info("MATCH", t.convert2string(), UVM_HIGH)

        cv_dim       = n;
        cv_singular  = t.singular;
        cv_overflow  = t.overflow;
        cv_frame_err = t.frame_err;
        cv_swap      = swaps_at_k0(n, t.a_loaded);
        result_cg.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCOREBOARD", $sformatf(
            "matrices=%0d mismatches=%0d coverage=%0.1f%% | compute cycles dim1..4 = %0d/%0d/%0d/%0d",
            n_checked, n_mismatch, result_cg.get_coverage(),
            cyc_dim[1], cyc_dim[2], cyc_dim[3], cyc_dim[4]), UVM_LOW)
        `uvm_info("SCOREBOARD", $sformatf(
            "precision vs double: diag-dominant max=%f mean=%f LSB (tol %f), any conditioning (report only) max=%f LSB over %0d matrices",
            max_err_dd, n_err_dd ? sum_err_dd / n_err_dd : 0.0, PREC_TOL_LSB, max_err_all, n_prec), UVM_LOW)
        if (n_mismatch != 0)
            `uvm_error("SCOREBOARD", $sformatf("%0d mismatches found", n_mismatch))
        if (n_checked == 0)
            `uvm_error("SCOREBOARD", "no matrix was checked")
    endfunction

endclass
