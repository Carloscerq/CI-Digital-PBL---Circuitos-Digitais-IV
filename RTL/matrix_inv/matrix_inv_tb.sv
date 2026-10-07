// ---------------------------------------------------------------------
//  matrix_inv_tb  --  self-checking directed + random bench for
//  matrix_inv.sv, no UVM needed (run_tests.sh builds it with Verilator).
//
//  Every matrix sent is also pushed through matrix_inv_ref_pkg::ref_inv
//  and the DUT has to match it exactly: every output word, the three
//  flags, the position of m_last, and the number of compute cycles.
//  For matrices marked check_prec (well-conditioned ones) the result is
//  also compared against a double-precision inverse; that error is the
//  "effect of fixed point" figure printed at the end, and anything over
//  PREC_TOL_LSB fails the run.
//
//  The input side inserts random idle gaps and the output side applies
//  random backpressure on m_ready, so the handshakes get exercised on
//  every matrix rather than in one dedicated test.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module matrix_inv_tb;

    import matrix_inv_ref_pkg::*;

    localparam int  DIM_W        = $clog2(N_MAX + 1);
    localparam real PREC_TOL_LSB = 2.0;
    localparam int  N_RANDOM     = 400;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic                     reset;
    logic                     s_valid, s_ready, s_last;
    logic signed [DATA_W-1:0] s_data;
    logic [DIM_W-1:0]         s_dim;
    logic                     m_valid, m_ready, m_last;
    logic signed [DATA_W-1:0] m_data;
    logic                     m_singular, m_overflow, m_frame_err;

    matrix_inv #(
        .N_MAX(N_MAX), .DATA_W(DATA_W), .FRAC_W(FRAC_W),
        .GUARD_W(GUARD_W), .INT_W(INT_W), .PIVOT_EPS(PIVOT_EPS)
    ) dut (
        .clk, .reset,
        .s_valid, .s_ready, .s_data, .s_last, .s_dim,
        .m_valid, .m_ready, .m_data, .m_last,
        .m_singular, .m_overflow, .m_frame_err
    );

    // -----------------------------------------------------------------
    //  Expected results, in send order
    // -----------------------------------------------------------------
    class expect_c;
        string name;
        int    dim;
        mat_t  a;            // what the DUT actually loaded
        mat_t  inv;
        bit    singular, overflow, frame_err, check_prec;
        int    cycles;
    endclass

    expect_c exp_q[$];

    int  errors      = 0;
    int  n_checked   = 0;
    int  n_singular  = 0;
    int  n_overflow  = 0;
    int  n_frame_err = 0;
    int  n_swapped   = 0;
    int  n_dim[N_MAX+1];
    int  cyc_dim[N_MAX+1];

    int  n_prec      = 0;
    real max_err_lsb = 0.0;
    real sum_err_lsb = 0.0;
    int  n_err_elems = 0;
    real max_resid   = 0.0;

    // $error would stop Verilator at the first failure; keep going and
    // report everything in the summary instead
    function automatic void fail(input string msg);
        $display("[%0t] ERROR: %s", $time, msg);
        errors++;
    endfunction

    bit  backpressure = 1'b1;
    int  max_gap      = 2;

    // -----------------------------------------------------------------
    //  Stimulus helpers
    // -----------------------------------------------------------------
    // send one matrix. dim_field is what goes on s_dim (normally dim);
    // last_at is the beat carrying s_last (-1: the correct one, the
    // dim*dim-th; >= dim*dim: never).
    task automatic send(
        input string name,
        input int    dim,
        input mat_t  a,
        input bit    check_prec = 1'b0,
        input int    dim_field  = -1,
        input int    last_at    = -1,
        input bit    expect_out = 1'b1
    );
        expect_c e;
        int      n_beats, n_sent;

        if (dim_field < 0) dim_field = dim;
        if (last_at < 0)   last_at   = dim*dim - 1;
        n_beats = (last_at < dim*dim) ? last_at + 1 : dim*dim;

        e = new();
        e.name       = name;
        e.dim        = dim;
        e.check_prec = check_prec;
        e.frame_err  = (last_at != dim*dim - 1);
        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < N_MAX; c++)
                e.a[r][c] = (r*dim + c < n_beats && r < dim && c < dim) ? a[r][c] : 0;
        ref_inv(dim, e.a, e.inv, e.singular, e.overflow, e.cycles);
        if (expect_out) exp_q.push_back(e);

        n_sent = 0;
        for (int r = 0; r < dim && n_sent < n_beats; r++)
            for (int c = 0; c < dim && n_sent < n_beats; c++) begin
                repeat ($urandom_range(max_gap)) begin
                    @(negedge clk);
                    s_valid = 1'b0;
                end
                @(negedge clk);
                s_valid = 1'b1;
                s_data  = DATA_W'(a[r][c]);
                s_last  = (n_sent == last_at);
                s_dim   = DIM_W'(dim_field);
                while (!s_ready) @(negedge clk);
                n_sent++;
            end
        @(negedge clk);
        s_valid = 1'b0;
        s_last  = 1'b0;
    endtask

    // -----------------------------------------------------------------
    //  Output check
    // -----------------------------------------------------------------
    int busy_cycles = 0;

    always @(negedge clk) begin
        if (reset)                      busy_cycles = 0;
        else if (!s_ready && !m_valid)  busy_cycles++;
    end

    initial begin : out_check
        expect_c e;
        int      got[N_MAX][N_MAX];
        int      cnt, cycles;
        bit      sing, ovf, ferr;
        rmat_t   ra, rinv;
        bit      rsing;

        m_ready = 1'b0;
        forever begin
            // wait for the first beat of a frame
            do @(negedge clk); while (!m_valid || reset);
            cycles = busy_cycles;
            busy_cycles = 0;

            if (exp_q.size() == 0) begin
                fail($sformatf("output frame with nothing expected"));
                e = null;
            end else begin
                e = exp_q.pop_front();
            end

            sing = m_singular;
            ovf  = m_overflow;
            ferr = m_frame_err;
            cnt  = 0;

            forever begin
                m_ready = backpressure ? ($urandom_range(3) != 0) : 1'b1;
                if (m_valid && m_ready) begin
                    if (e != null) begin
                        got[cnt / e.dim][cnt % e.dim] = int'(m_data);
                        if (m_last != (cnt == e.dim*e.dim - 1)) begin
                            fail($sformatf("[%s] m_last=%0b at beat %0d", e.name, m_last, cnt));
                        end
                    end
                    if (m_singular !== sing || m_overflow !== ovf || m_frame_err !== ferr) begin
                        fail($sformatf("flags changed mid-frame"));
                    end
                    cnt++;
                    if (m_last) break;
                end
                @(negedge clk);
                if (reset) break;
            end
            // hold m_ready through the edge that takes the last beat
            @(posedge clk);
            #1 m_ready = 1'b0;
            if (reset || e == null) continue;

            // ---------------- bit-exact check ----------------
            n_checked++;
            n_dim[e.dim]++;
            cyc_dim[e.dim] = cycles;
            if (e.singular)  n_singular++;
            if (e.overflow)  n_overflow++;
            if (e.frame_err) n_frame_err++;
            if (swaps_at_k0(e.dim, e.a)) n_swapped++;

            if (cnt != e.dim*e.dim) begin
                fail($sformatf("[%s] %0d output beats, expected %0d", e.name, cnt, e.dim*e.dim));
            end
            if (sing != e.singular || ovf != e.overflow || ferr != e.frame_err) begin
                fail($sformatf("[%s] flags singular/overflow/frame_err = %0b%0b%0b, expected %0b%0b%0b",
                       e.name, sing, ovf, ferr, e.singular, e.overflow, e.frame_err));
            end
            if (cycles != e.cycles) begin
                fail($sformatf("[%s] %0d compute cycles, expected %0d", e.name, cycles, e.cycles));
            end
            for (int r = 0; r < e.dim; r++)
                for (int c = 0; c < e.dim; c++)
                    if (got[r][c] != e.inv[r][c]) begin
                        fail($sformatf("[%s] inv[%0d][%0d] = %0d (%f), expected %0d (%f)",
                               e.name, r, c, got[r][c], from_q(got[r][c]),
                               e.inv[r][c], from_q(e.inv[r][c])));
                    end

            // ---------------- precision vs double ----------------
            if (e.check_prec && !e.singular && !e.overflow) begin
                real err, resid, acc;
                to_real_mat(e.a, ra);
                real_inv(e.dim, ra, rinv, rsing);
                n_prec++;
                for (int r = 0; r < e.dim; r++)
                    for (int c = 0; c < e.dim; c++) begin
                        err = from_q(got[r][c]) - rinv[r][c];
                        err = (err < 0 ? -err : err) / LSB;
                        sum_err_lsb += err;
                        n_err_elems++;
                        if (err > max_err_lsb) max_err_lsb = err;
                        if (err > PREC_TOL_LSB) begin
                            fail($sformatf("[%s] inv[%0d][%0d] off by %f LSB from the exact inverse",
                                   e.name, r, c, err));
                        end
                        // residual of A * inv against I
                        acc = 0.0;
                        for (int t = 0; t < e.dim; t++)
                            acc += ra[r][t] * from_q(got[t][c]);
                        resid = acc - ((r == c) ? 1.0 : 0.0);
                        resid = resid < 0 ? -resid : resid;
                        if (resid > max_resid) max_resid = resid;
                    end
            end
        end
    end

    // -----------------------------------------------------------------
    //  Test sequence
    // -----------------------------------------------------------------
    task automatic wait_drain();
        int guard = 0;
        while (exp_q.size() != 0 && guard < 100000) begin
            @(negedge clk);
            guard++;
        end
        if (exp_q.size() != 0) begin
            fail($sformatf("timeout: %0d results never came out", exp_q.size()));
        end
        repeat (3) @(negedge clk);
    endtask

    task automatic random_diag_dominant(input int n);
        mat_t a;
        real  s, d;
        int   dim;
        repeat (n) begin
            dim = $urandom_range(N_MAX, 1);
            for (int r = 0; r < N_MAX; r++) begin
                s = 0.0;
                for (int c = 0; c < N_MAX; c++) begin
                    a[r][c] = (r < dim && c < dim && r != c)
                            ? $urandom_range(2*to_q(2.0)) - to_q(2.0) : 0;
                    s += (a[r][c] < 0 ? -from_q(a[r][c]) : from_q(a[r][c]));
                end
                d = s + 0.5 + from_q($urandom_range(to_q(4.0)));
                if (r < dim) a[r][r] = ($urandom_range(1) ? to_q(d) : -to_q(d));
            end
            send("rand_diag_dominant", dim, a, 1'b1);
        end
    endtask

    task automatic random_general(input int n);
        mat_t a;
        int   dim;
        repeat (n) begin
            dim = $urandom_range(N_MAX, 1);
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++)
                    a[r][c] = (r < dim && c < dim) ? $urandom_range(2*to_q(8.0)) - to_q(8.0) : 0;
            send("rand_general", dim, a);
        end
    endtask

    // small integer entries: lots of equal |a[i][k]| candidates, so the
    // pivot tie-break (first row wins) and singular cases get exercised
    task automatic random_small_int(input int n);
        mat_t a;
        int   dim;
        repeat (n) begin
            dim = $urandom_range(N_MAX, 2);
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++)
                    a[r][c] = (r < dim && c < dim) ? to_q(real'($urandom_range(6)) - 3.0) : 0;
            send("rand_small_int", dim, a);
        end
    endtask

    initial begin : stimulus
        mat_t a;
        real  eps;

        eps = real'(PIVOT_EPS) * LSB;

        reset   = 1'b1;
        s_valid = 1'b0;
        s_last  = 1'b0;
        s_data  = '0;
        s_dim   = '0;
        repeat (2) @(negedge clk);
        reset = 1'b0;

        // ---- identity, every size ----
        for (int n = 1; n <= N_MAX; n++) begin
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++)
                    a[r][c] = (r == c && r < n) ? to_q(1.0) : 0;
            send($sformatf("identity_%0d", n), n, a, 1'b1);
        end

        // ---- exact inverses ----
        send("scalar",    1, mk(1, "-0.25"), 1'b1);
        send("diagonal",  4, mk(4, "2 0 0 0  0 -4 0 0  0 0 0.5 0  0 0 0 8"), 1'b1);
        send("int_2x2",   2, mk(2, "4 7  2 6"), 1'b1);
        send("tridiag",   3, mk(3, "2 -1 0  -1 2 -1  0 -1 2"), 1'b1);
        send("lower_tri", 4, mk(4, "1 0 0 0  1 1 0 0  1 1 1 0  1 1 1 1"), 1'b1);
        send("dense_4x4", 4, mk(4, "4 -2 1 3  3 6 -4 2  2 1 8 -5  1 3 -2 7"), 1'b1);

        // ---- pivoting: zero / small leading entries ----
        send("swap_2x2",  2, mk(2, "0 1  1 0"), 1'b1);
        send("perm_3x3",  3, mk(3, "0 0 1  1 0 0  0 1 0"), 1'b1);
        send("zero_a00",  4, mk(4, "0 2 1 0  1 0 0 3  0 1 0 1  2 0 1 0"), 1'b1);
        send("small_a00", 3, mk(3, "0.001 1 2  1 3 1  2 1 4"), 1'b1);
        send("tie_pivot", 3, mk(3, "3 1 2  -3 2 1  3 5 7"), 1'b1);
        send("neg_pivot", 3, mk(3, "-5 1 0  1 -3 1  0 1 -4"), 1'b1);

        // ---- singular: pivot below PIVOT_EPS ----
        send("dep_rows",  2, mk(2, "1 2  2 4"));
        send("zero_row",  3, mk(3, "1 2 3  0 0 0  4 5 6"));
        send("rank3",     4, mk(4, "1 2 3 4  2 0 1 1  3 2 4 5  0 1 1 2"));
        send("all_zero",  4, mk(4, ""));
        send("below_eps", 2, mk(2, $sformatf("1 0 0 %.10f", eps/2)));

        // ---- overflow: the inverse does not fit in Q9.15 ----
        send("above_eps", 2, mk(2, $sformatf("1 0 0 %.10f", eps*2)));
        send("ill_cond",  2, mk(2, "1 1  1 1.00390625"));
        send("big_inv",   1, mk(1, "0.003"));

        // ---- s_dim = 0 means N_MAX ----
        send("dim_field_0", 4, mk(4, "2 0 0 0  0 2 0 0  0 0 2 0  0 0 0 2"), 1'b1, 0);

        // ---- framing errors ----
        send("early_last",   3, mk(3, "1 2 3  4 5 6  7 8 10"), 1'b0, -1, 4);
        send("missing_last", 2, mk(2, "3 1  1 2"), 1'b0, -1, 100);
        send("after_err",    2, mk(2, "3 1  1 2"), 1'b1);

        // ---- reset in the middle of a computation ----
        wait_drain();
        send("reset_victim", 4, mk(4, "4 -2 1 3  3 6 -4 2  2 1 8 -5  1 3 -2 7"),
             1'b0, -1, -1, 1'b0);
        repeat (40) @(negedge clk);
        if (s_ready) begin
            fail($sformatf("reset test: DUT was not busy"));
        end
        reset = 1'b1;
        @(negedge clk);
        reset = 1'b0;
        @(negedge clk);
        if (!s_ready || m_valid) begin
            fail($sformatf("reset test: DUT did not return to idle"));
        end
        send("after_reset", 2, mk(2, "4 7  2 6"), 1'b1);

        // ---- random ----
        random_diag_dominant(N_RANDOM);
        random_general(N_RANDOM);
        random_small_int(N_RANDOM);

        // ---- back to back with no gaps and no backpressure ----
        wait_drain();
        max_gap      = 0;
        backpressure = 1'b0;
        random_diag_dominant(50);

        wait_drain();

        $display("");
        $display("==================== matrix_inv_tb ====================");
        $display(" matrices checked     : %0d", n_checked);
        $display("   by dim 1/2/3/4     : %0d / %0d / %0d / %0d",
                 n_dim[1], n_dim[2], n_dim[3], n_dim[4]);
        $display("   singular           : %0d", n_singular);
        $display("   overflow           : %0d", n_overflow);
        $display("   frame error        : %0d", n_frame_err);
        $display("   row swap at k=0    : %0d", n_swapped);
        $display(" compute cycles 1/2/3/4: %0d / %0d / %0d / %0d",
                 cyc_dim[1], cyc_dim[2], cyc_dim[3], cyc_dim[4]);
        $display(" precision vs double (%0d well-conditioned matrices):", n_prec);
        $display("   max |error|        : %f LSB (tolerance %f)", max_err_lsb, PREC_TOL_LSB);
        $display("   mean |error|       : %f LSB", n_err_elems ? sum_err_lsb / n_err_elems : 0.0);
        $display("   max |A*inv - I|    : %e", max_resid);
        $display(" errors               : %0d", errors);
        $display("=======================================================");
        if (errors != 0) $fatal(1, "matrix_inv_tb: FAILED");
        $display("matrix_inv_tb: PASSED");
        $finish;
    end

endmodule
