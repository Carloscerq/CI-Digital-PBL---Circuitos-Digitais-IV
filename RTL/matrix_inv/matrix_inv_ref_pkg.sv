// ---------------------------------------------------------------------
//  matrix_inv_ref_pkg  --  reference models for matrix_inv.sv, shared
//  by the directed testbench (matrix_inv_tb.sv) and the UVM scoreboard
//  (uvm/matrix_inv_scoreboard.sv). No UVM in here, so the directed
//  bench builds without a UVM library.
//
//  ref_inv()   bit-exact model of the RTL: same augmented layout, same
//              pivot rule (first strictly larger magnitude wins), same
//              truncating reciprocal, same round-half-up multiply, same
//              symmetric saturation, same forced 1/0 on the pivot
//              column. It also returns the number of compute cycles the
//              RTL should take (last input beat -> first output beat),
//              so a bench can check the documented cycle count too.
//              Anything it disagrees with the DUT on is an RTL bug.
//
//  real_inv()  plain double-precision Gauss-Jordan with partial
//              pivoting. Used only to measure how far the fixed-point
//              result is from the exact inverse.
//
//  mk()        builds a test matrix from a string of reals, so directed
//              cases read like the matrix they are.
//
//  The localparams below must match the DUT's parameters; both benches
//  instantiate matrix_inv with these values so they cannot drift.
// ---------------------------------------------------------------------
package matrix_inv_ref_pkg;

    localparam int N_MAX     = 4;
    localparam int DATA_W    = 24;
    localparam int FRAC_W    = 15;
    localparam int GUARD_W   = 5;
    localparam int INT_W     = 32;
    localparam int PIVOT_EPS = 32;

    localparam int IFRAC = FRAC_W + GUARD_W;
    localparam int QW    = 2*IFRAC + 1;

    localparam longint MAXV    = (64'sd1 <<< (INT_W-1)) - 1;
    localparam longint ONE_I   = 64'sd1 <<< IFRAC;
    localparam longint EPS_I   = longint'(PIVOT_EPS) <<< GUARD_W;
    localparam longint OUT_MAX = (64'sd1 <<< (DATA_W-1)) - 1;

    localparam real LSB = 1.0 / (1 << FRAC_W);

    typedef int  mat_t  [N_MAX][N_MAX];   // raw Q9.15 words
    typedef real rmat_t [N_MAX][N_MAX];

    // -----------------------------------------------------------------
    //  Fixed-point primitives, one per RTL helper
    // -----------------------------------------------------------------
    function automatic longint sat_int(input longint x, inout bit ovf);
        if (x > MAXV)  begin ovf = 1'b1; return MAXV;  end
        if (x < -MAXV) begin ovf = 1'b1; return -MAXV; end
        return x;
    endfunction

    function automatic longint mulr(input longint a, input longint b, inout bit ovf);
        longint p;
        p = (a * b + (64'sd1 <<< (IFRAC-1))) >>> IFRAC;
        return sat_int(p, ovf);
    endfunction

    function automatic longint subs(input longint a, input longint b, inout bit ovf);
        return sat_int(a - b, ovf);
    endfunction

    function automatic int to_out(input longint x, inout bit ovf);
        longint r;
        r = (x + (64'sd1 <<< (GUARD_W-1))) >>> GUARD_W;
        if (r > OUT_MAX)  begin ovf = 1'b1; return int'(OUT_MAX);  end
        if (r < -OUT_MAX) begin ovf = 1'b1; return int'(-OUT_MAX); end
        return int'(r);
    endfunction

    function automatic longint absl(input longint x);
        return (x < 0) ? -x : x;
    endfunction

    // -----------------------------------------------------------------
    //  Bit-exact model
    // -----------------------------------------------------------------
    function automatic void ref_inv(
        input  int   dim,
        input  mat_t a,
        output mat_t inv,
        output bit   singular,
        output bit   overflow,
        output int   cycles
    );
        longint aug [N_MAX][2*N_MAX];
        longint best_abs, q, recip, f;
        int     best_row, col;
        bit     pneg, ovf;

        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < 2*N_MAX; c++)
                aug[r][c] = (c == N_MAX + r) ? ONE_I : 64'sd0;
        for (int r = 0; r < dim; r++)
            for (int c = 0; c < dim; c++)
                aug[r][c] = longint'(a[r][c]) <<< GUARD_W;

        singular = 1'b0;
        ovf      = 1'b0;
        cycles   = 0;

        for (int k = 0; k < dim; k++) begin
            // PIVOT + SWAP
            best_row = k;
            best_abs = absl(aug[k][k]);
            for (int i = k + 1; i < dim; i++)
                if (absl(aug[i][k]) > best_abs) begin
                    best_abs = absl(aug[i][k]);
                    best_row = i;
                end
            cycles += (dim - k) + 1;

            if (best_abs < EPS_I) begin
                singular = 1'b1;
                break;
            end

            for (int c = 0; c < 2*N_MAX; c++) begin
                longint t;
                t                = aug[k][c];
                aug[k][c]        = aug[best_row][c];
                aug[best_row][c] = t;
            end

            // RECIP: floor(2^(2*IFRAC) / |p|), what a restoring divider gives
            pneg  = aug[k][k] < 0;
            q     = sat_int((64'sd1 <<< (2*IFRAC)) / best_abs, ovf);
            recip = pneg ? -q : q;
            cycles += QW;

            // NORM
            for (int j = 0; j < 2*dim; j++) begin
                col = (j < dim) ? j : N_MAX + j - dim;
                if (col == k) aug[k][col] = ONE_I;
                else          aug[k][col] = mulr(aug[k][col], recip, ovf);
            end
            cycles += 2*dim;

            // ELIM
            for (int i = 0; i < dim; i++) begin
                if (i == k) continue;
                f = aug[i][k];
                for (int j = 0; j < 2*dim; j++) begin
                    col = (j < dim) ? j : N_MAX + j - dim;
                    if (col == k) aug[i][col] = 0;
                    else          aug[i][col] = subs(aug[i][col], mulr(f, aug[k][col], ovf), ovf);
                end
            end
            cycles += (dim - 1) * 2*dim;
        end

        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < N_MAX; c++)
                inv[r][c] = 0;

        if (singular) begin
            overflow = 1'b0;
        end else begin
            for (int r = 0; r < dim; r++)
                for (int c = 0; c < dim; c++)
                    inv[r][c] = to_out(aug[r][N_MAX + c], ovf);
            overflow = ovf;
        end
    endfunction

    // -----------------------------------------------------------------
    //  Double-precision model
    // -----------------------------------------------------------------
    function automatic void real_inv(
        input  int    dim,
        input  rmat_t a,
        output rmat_t inv,
        output bit    singular
    );
        real aug [N_MAX][2*N_MAX];
        real p, f, t;
        int  best;

        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < 2*N_MAX; c++)
                aug[r][c] = (c < N_MAX) ? ((r < dim && c < dim) ? a[r][c] : 0.0)
                                        : ((c - N_MAX == r) ? 1.0 : 0.0);
        singular = 1'b0;

        for (int k = 0; k < dim; k++) begin
            best = k;
            for (int i = k + 1; i < dim; i++)
                if ((aug[i][k] < 0 ? -aug[i][k] : aug[i][k]) >
                    (aug[best][k] < 0 ? -aug[best][k] : aug[best][k]))
                    best = i;
            p = aug[best][k];
            if ((p < 0 ? -p : p) < 1.0e-12) begin
                singular = 1'b1;
                break;
            end
            for (int c = 0; c < 2*N_MAX; c++) begin
                t = aug[k][c]; aug[k][c] = aug[best][c]; aug[best][c] = t;
            end
            for (int c = 0; c < 2*N_MAX; c++) aug[k][c] = aug[k][c] / p;
            for (int i = 0; i < dim; i++) begin
                if (i == k) continue;
                f = aug[i][k];
                for (int c = 0; c < 2*N_MAX; c++) aug[i][c] = aug[i][c] - f * aug[k][c];
            end
        end

        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < N_MAX; c++)
                inv[r][c] = singular ? 0.0 : aug[r][N_MAX + c];
    endfunction

    // -----------------------------------------------------------------
    //  Conversions
    // -----------------------------------------------------------------
    // real -> Q9.15; int'() of a real rounds to nearest, ties away from 0
    function automatic int to_q(input real x);
        return int'(x * (1 << FRAC_W));
    endfunction

    function automatic real from_q(input int x);
        return real'(x) * LSB;
    endfunction

    function automatic void to_real_mat(input mat_t m, output rmat_t r);
        for (int i = 0; i < N_MAX; i++)
            for (int j = 0; j < N_MAX; j++)
                r[i][j] = from_q(m[i][j]);
    endfunction

    // -----------------------------------------------------------------
    //  Stimulus helpers
    // -----------------------------------------------------------------
    // dim x dim matrix from a row-major, whitespace-separated list of
    // reals, e.g. mk(2, "4 7  2 6"); missing trailing values are zero
    function automatic mat_t mk(input int dim, input string v);
        mat_t  m;
        string tok;
        real   x;
        int    idx;

        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < N_MAX; c++)
                m[r][c] = 0;
        idx = 0;
        tok = "";
        for (int i = 0; i <= v.len(); i++) begin
            if (i == v.len() || v[i] == " ") begin
                if (tok.len() != 0) begin
                    void'($sscanf(tok, "%f", x));
                    if (idx < dim*dim) m[idx / dim][idx % dim] = to_q(x);
                    idx++;
                    tok = "";
                end
            end else begin
                tok = {tok, string'(v[i])};
            end
        end
        return m;
    endfunction

    // true if partial pivoting picks a row other than 0 for column 0
    function automatic bit swaps_at_k0(input int dim, input mat_t a);
        for (int i = 1; i < dim; i++)
            if ((a[i][0] < 0 ? -a[i][0] : a[i][0]) > (a[0][0] < 0 ? -a[0][0] : a[0][0]))
                return 1;
        return 0;
    endfunction

endpackage
