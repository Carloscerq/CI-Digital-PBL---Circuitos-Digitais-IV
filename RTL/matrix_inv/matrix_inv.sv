// ---------------------------------------------------------------------
//  matrix_inv  --  inverse of a square matrix of runtime size 1..N_MAX
//                  (N_MAX = 4 by default), by Gauss-Jordan elimination
//                  with partial pivoting.
//
//  Interface (same plain valid/ready/last contract as the rest of RTL/):
//    s_*  the N x N input matrix, row-major, one Q9.15 element per beat.
//         s_dim is sampled on the first beat of a frame (0 or > N_MAX is
//         treated as N_MAX). The frame ends at whichever comes first:
//         s_last, or the dim*dim-th beat. If those two disagree the
//         frame is still processed (missing elements read as zero) and
//         m_frame_err is raised with the result.
//    m_*  the N x N inverse, row-major, Q9.15, one element per beat.
//         m_singular / m_overflow / m_frame_err are held for the whole
//         output frame. When m_singular is set m_data is all zeros and
//         m_overflow is forced low.
//  One matrix in flight at a time: s_ready is low from the last input
//  beat until the last output beat has been accepted.
//
//  Storage: the augmented matrix [A | I] lives in registers,
//  aug[N_MAX][2*N_MAX]. A is always in columns 0..dim-1 and I/A^-1 in
//  columns N_MAX..N_MAX+dim-1, so the column map never depends on dim
//  for the right half. 32 words is too small to be worth an M10K, and
//  registers let a row swap happen in a single cycle.
//
//  Internal format: Q(INT_W-IFRAC).IFRAC = Q12.20 by default -- GUARD_W
//  extra fraction bits over the I/O format so rounding error does not
//  pile up across the N elimination passes, and more integer headroom
//  for intermediate values. Every multiply rounds half-up back to IFRAC
//  bits; every multiply/subtract saturates symmetrically to
//  +-(2^(INT_W-1)-1) and sets the sticky overflow flag when it does.
//  Results round half-up to Q9.15 and saturate on the way out.
//
//  Per pivot column k:
//    PIVOT   scan rows k..dim-1 for max |a[i][k]|        dim-k cycles
//    SWAP    |pivot| < PIVOT_EPS -> singular, stop;       1 cycle
//            else swap row k with the pivot row
//    RECIP   r = 1/pivot, restoring divider               2*IFRAC+1 cycles
//    NORM    row k *= r  (a[k][k] forced to exactly 1)    2*dim cycles
//    ELIM    row i -= a[i][k] * row k, i != k             (dim-1)*2*dim cycles
//            (a[i][k] forced to exactly 0)
//  Datapath: one signed INT_W x INT_W multiplier, one subtractor, the
//  divider's (INT_W+1)-bit compare/subtract, and a magnitude comparator.
//  Only one reciprocal per column is computed; everything else is
//  multiplication.
//
//  Cycle count, dim = n, default parameters (load and unload excluded):
//    sum_k (n-k) + n*(1 + 41 + 2n + 2n(n-1)) = n(n+1)/2 + n*(42 + 2n^2)
//    n=2: 103   n=3: 186   n=4: 306     (+ n^2 load + n^2 unload beats)
//  A 4x4 inversion is ~340 cycles end to end, ~6.8 us at 50 MHz.
//
//  Division by zero: the reciprocal is never started for a pivot below
//  PIVOT_EPS (in Q9.15 LSBs). With partial pivoting the pivot is the
//  largest magnitude left in its column, so a small pivot means the
//  matrix is singular (or too ill-conditioned for this format).
//  PIVOT_EPS also bounds the reciprocal: 1/PIVOT_EPS must fit in INT_W,
//  which the assertion below checks.
// ---------------------------------------------------------------------
module matrix_inv #(
    parameter int N_MAX     = 4,
    parameter int DATA_W    = 24,   // I/O word, Q9.15
    parameter int FRAC_W    = 15,
    parameter int GUARD_W   = 5,    // extra internal fraction bits
    parameter int INT_W     = 32,   // internal word, Q12.20
    parameter int PIVOT_EPS = 32,   // in Q9.15 LSBs: 32 = 2^-10
    parameter int DIM_W     = $clog2(N_MAX + 1)
) (
    input  logic                     clk,
    input  logic                     reset,

    input  logic                     s_valid,
    output logic                     s_ready,
    input  logic signed [DATA_W-1:0] s_data,
    input  logic                     s_last,
    input  logic [DIM_W-1:0]         s_dim,

    output logic                     m_valid,
    input  logic                     m_ready,
    output logic signed [DATA_W-1:0] m_data,
    output logic                     m_last,
    output logic                     m_singular,
    output logic                     m_overflow,
    output logic                     m_frame_err
);

    localparam int IFRAC  = FRAC_W + GUARD_W;
    localparam int QW     = 2*IFRAC + 1;           // quotient bits of 2^(2*IFRAC) / |p|
    localparam int NCOL   = 2*N_MAX;
    localparam int ROW_W  = DIM_W;
    localparam int COL_W  = $clog2(NCOL + 1);
    localparam int LD_W   = $clog2(N_MAX*N_MAX + 1);
    localparam int DIV_W  = $clog2(QW);

    localparam logic signed [INT_W-1:0]  MAXV    = {1'b0, {(INT_W-1){1'b1}}};
    localparam logic signed [INT_W-1:0]  MINV    = -MAXV;
    localparam logic signed [INT_W-1:0]  ONE_I   = INT_W'(1) <<< IFRAC;
    localparam logic        [INT_W-1:0]  EPS_I   = INT_W'(PIVOT_EPS) << GUARD_W;
    localparam logic signed [DATA_W-1:0] OUT_MAX = {1'b0, {(DATA_W-1){1'b1}}};
    localparam logic signed [DATA_W-1:0] OUT_MIN = -OUT_MAX;

    initial begin
        // 2^(2*IFRAC) / EPS_I must fit in INT_W-1 bits, or a pivot just
        // above the threshold would saturate its own reciprocal.
        assert ((2*IFRAC) - $clog2(PIVOT_EPS << GUARD_W) < INT_W - 1)
            else $fatal(1, "matrix_inv: PIVOT_EPS too small for INT_W");
        assert (INT_W >= DATA_W + GUARD_W + 1)
            else $fatal(1, "matrix_inv: INT_W too narrow for DATA_W + GUARD_W");
    end

    // -----------------------------------------------------------------
    //  Arithmetic helpers
    // -----------------------------------------------------------------
    function automatic logic signed [INT_W-1:0] sat_int(
        input  logic signed [2*INT_W-1:0] x,
        output logic                      sat
    );
        sat = 1'b0;
        if (x > (2*INT_W)'(MAXV))      begin sat = 1'b1; return MAXV; end
        else if (x < (2*INT_W)'(MINV)) begin sat = 1'b1; return MINV; end
        return x[INT_W-1:0];
    endfunction

    // a*b in the internal format, rounded half-up, saturated
    function automatic logic signed [INT_W-1:0] mulr(
        input  logic signed [INT_W-1:0] a,
        input  logic signed [INT_W-1:0] b,
        output logic                    sat
    );
        logic signed [2*INT_W-1:0] p;
        p = a * b;
        p = (p + (2*INT_W)'(1 <<< (IFRAC-1))) >>> IFRAC;
        return sat_int(p, sat);
    endfunction

    function automatic logic signed [INT_W-1:0] subs(
        input  logic signed [INT_W-1:0] a,
        input  logic signed [INT_W-1:0] b,
        output logic                    sat
    );
        logic signed [2*INT_W-1:0] d;
        d = a - b;
        return sat_int(d, sat);
    endfunction

    function automatic logic [INT_W-1:0] mag(input logic signed [INT_W-1:0] x);
        return (x < 0) ? INT_W'(-x) : INT_W'(x);
    endfunction

    // internal -> Q9.15, rounded half-up, saturated
    function automatic logic signed [DATA_W-1:0] to_out(
        input  logic signed [INT_W-1:0] x,
        output logic                    sat
    );
        logic signed [INT_W:0] r;
        r   = (x + (INT_W+1)'(1 <<< (GUARD_W-1))) >>> GUARD_W;
        sat = 1'b0;
        if (r > (INT_W+1)'(OUT_MAX))      begin sat = 1'b1; return OUT_MAX; end
        else if (r < (INT_W+1)'(OUT_MIN)) begin sat = 1'b1; return OUT_MIN; end
        return r[DATA_W-1:0];
    endfunction

    // augmented-matrix column for sweep index j = 0..2*dim-1
    function automatic logic [COL_W-1:0] col_of(
        input logic [COL_W-1:0] j,
        input logic [ROW_W-1:0] dim
    );
        return (j < COL_W'(dim)) ? j : COL_W'(N_MAX) + j - COL_W'(dim);
    endfunction

    // -----------------------------------------------------------------
    //  State
    // -----------------------------------------------------------------
    typedef enum logic [2:0] {
        S_LOAD, S_PIVOT, S_SWAP, S_RECIP, S_NORM, S_ELIM, S_OUT
    } state_t;

    state_t state;

    logic signed [INT_W-1:0] aug [N_MAX][NCOL];

    logic [ROW_W-1:0] dim_r;
    logic [ROW_W-1:0] ld_row, ld_col;
    logic [LD_W-1:0]  ld_cnt;

    logic [ROW_W-1:0] k;          // pivot column
    logic [ROW_W-1:0] pi;         // pivot-search row
    logic [ROW_W-1:0] best_row;
    logic [INT_W-1:0] best_abs;

    logic             piv_neg;
    logic [INT_W-1:0] piv_abs;
    logic [INT_W:0]   rem;
    logic [QW-1:0]    quo;
    logic [DIV_W-1:0] div_cnt;
    logic signed [INT_W-1:0] recip;

    logic [COL_W-1:0] j;          // column sweep in NORM / ELIM
    logic [ROW_W-1:0] ei;         // row being eliminated
    logic signed [INT_W-1:0] factor;

    logic [ROW_W-1:0] out_row, out_col;

    logic singular, ovf, frame_err;

    assign s_ready = (state == S_LOAD);

    // -----------------------------------------------------------------
    //  Output side (combinational off the stable register file)
    // -----------------------------------------------------------------
    logic signed [DATA_W-1:0] out_word;
    logic                     out_word_sat;
    logic                     out_sat_any;

    always_comb begin
        out_word = to_out(aug[out_row][N_MAX + out_col], out_word_sat);
    end

    always_comb begin : sat_scan
        logic signed [DATA_W-1:0] tmp;
        logic                     s;
        out_sat_any = 1'b0;
        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < N_MAX; c++) begin
                tmp = to_out(aug[r][N_MAX + c], s);
                if (r < dim_r && c < dim_r && s) out_sat_any = 1'b1;
            end
    end

    assign m_valid     = (state == S_OUT);
    assign m_data      = singular ? '0 : out_word;
    assign m_last      = (out_row == dim_r - 1'b1) && (out_col == dim_r - 1'b1);
    assign m_singular  = singular;
    assign m_overflow  = !singular && (ovf || out_sat_any);
    assign m_frame_err = frame_err;

    // -----------------------------------------------------------------
    //  Control + datapath
    // -----------------------------------------------------------------
    // first row ELIM visits for column kk: 0, or 1 when kk == 0
    function automatic logic [ROW_W-1:0] first_elim_row(input logic [ROW_W-1:0] kk);
        return (kk == 0) ? ROW_W'(1) : ROW_W'(0);
    endfunction

    task automatic clear_aug();
        for (int r = 0; r < N_MAX; r++)
            for (int c = 0; c < NCOL; c++)
                aug[r][c] <= (c == N_MAX + r) ? ONE_I : '0;
    endtask

    // advance to the next pivot column, or to the output phase
    task automatic next_column();
        if (k == dim_r - 1'b1) begin
            out_row <= '0;
            out_col <= '0;
            state   <= S_OUT;
        end else begin
            k     <= k + 1'b1;
            pi    <= k + 1'b1;
            state <= S_PIVOT;
        end
    endtask

    always_ff @(posedge clk) begin
        if (reset) begin
            state     <= S_LOAD;
            clear_aug();
            dim_r     <= ROW_W'(N_MAX);
            ld_row    <= '0;
            ld_col    <= '0;
            ld_cnt    <= '0;
            k         <= '0;
            pi        <= '0;
            best_row  <= '0;
            best_abs  <= '0;
            piv_neg   <= 1'b0;
            piv_abs   <= '0;
            rem       <= '0;
            quo       <= '0;
            div_cnt   <= '0;
            recip     <= '0;
            j         <= '0;
            ei        <= '0;
            factor    <= '0;
            out_row   <= '0;
            out_col   <= '0;
            singular  <= 1'b0;
            ovf       <= 1'b0;
            frame_err <= 1'b0;
        end else begin
            case (state)

            // ---------------------------------------------------------
            S_LOAD: if (s_valid) begin : load
                logic [ROW_W-1:0] dim_cur;
                logic             final_beat;

                if (ld_cnt == 0) begin
                    dim_cur  = (s_dim == 0 || s_dim > DIM_W'(N_MAX)) ? ROW_W'(N_MAX) : ROW_W'(s_dim);
                    dim_r    <= dim_cur;
                    singular <= 1'b0;
                    ovf      <= 1'b0;
                end else begin
                    dim_cur = dim_r;
                end

                final_beat = (int'(ld_cnt) == int'(dim_cur) * int'(dim_cur) - 1);
                frame_err  <= ((ld_cnt == 0) ? 1'b0 : frame_err) | (final_beat != s_last);

                aug[ld_row][ld_col] <= INT_W'(s_data) <<< GUARD_W;

                if (final_beat || s_last) begin
                    ld_row <= '0;
                    ld_col <= '0;
                    ld_cnt <= '0;
                    k      <= '0;
                    pi     <= '0;
                    state  <= S_PIVOT;
                end else begin
                    ld_cnt <= ld_cnt + 1'b1;
                    if (ld_col == dim_cur - 1'b1) begin
                        ld_col <= '0;
                        ld_row <= ld_row + 1'b1;
                    end else begin
                        ld_col <= ld_col + 1'b1;
                    end
                end
            end

            // ---------------------------------------------------------
            S_PIVOT: begin : pivot
                logic [INT_W-1:0] v;
                v = mag(aug[pi][k]);
                if (pi == k || v > best_abs) begin
                    best_abs <= v;
                    best_row <= pi;
                end
                if (pi == dim_r - 1'b1) state <= S_SWAP;
                else                    pi    <= pi + 1'b1;
            end

            // ---------------------------------------------------------
            S_SWAP: begin
                if (best_abs < EPS_I) begin
                    singular <= 1'b1;
                    out_row  <= '0;
                    out_col  <= '0;
                    state    <= S_OUT;
                end else begin
                    for (int c = 0; c < NCOL; c++) begin
                        aug[k][c]        <= aug[best_row][c];
                        aug[best_row][c] <= aug[k][c];
                    end
                    piv_neg <= aug[best_row][k] < 0;
                    piv_abs <= best_abs;
                    rem     <= '0;
                    quo     <= '0;
                    div_cnt <= DIV_W'(QW - 1);
                    state   <= S_RECIP;
                end
            end

            // ---------------------------------------------------------
            //  Restoring division of 2^(2*IFRAC) by |pivot|: the dividend
            //  has a single set bit, so it is shifted in as
            //  (div_cnt == QW-1) instead of being held in a register.
            S_RECIP: begin : recip_step
                logic [INT_W:0]  rem_sh;
                logic            qbit;
                logic [QW-1:0]   q_next;
                logic            s;

                rem_sh = {rem[INT_W-1:0], (div_cnt == DIV_W'(QW - 1))};
                if (rem_sh >= (INT_W+1)'(piv_abs)) begin
                    rem  <= rem_sh - (INT_W+1)'(piv_abs);
                    qbit = 1'b1;
                end else begin
                    rem  <= rem_sh;
                    qbit = 1'b0;
                end
                q_next = {quo[QW-2:0], qbit};
                quo    <= q_next;

                if (div_cnt == 0) begin
                    logic signed [2*INT_W-1:0] q_s;
                    logic signed [INT_W-1:0]   q_mag;
                    q_s   = (2*INT_W)'(q_next);
                    q_mag = sat_int(q_s, s);
                    recip <= piv_neg ? -q_mag : q_mag;
                    if (s) ovf <= 1'b1;
                    j     <= '0;
                    state <= S_NORM;
                end else begin
                    div_cnt <= div_cnt - 1'b1;
                end
            end

            // ---------------------------------------------------------
            S_NORM: begin : norm
                logic [COL_W-1:0]        col;
                logic signed [INT_W-1:0] p;
                logic                    s;

                col = col_of(j, dim_r);
                if (col == COL_W'(k)) begin
                    aug[k][col] <= ONE_I;
                end else begin
                    p = mulr(aug[k][col], recip, s);
                    aug[k][col] <= p;
                    if (s) ovf <= 1'b1;
                end

                if (int'(j) == 2*int'(dim_r) - 1) begin
                    j <= '0;
                    if (first_elim_row(k) < dim_r) begin
                        ei    <= first_elim_row(k);
                        state <= S_ELIM;
                    end else begin
                        next_column();
                    end
                end else begin
                    j <= j + 1'b1;
                end
            end

            // ---------------------------------------------------------
            S_ELIM: begin : elim
                logic [COL_W-1:0]        col;
                logic signed [INT_W-1:0] f, p, d;
                logic                    s1, s2;
                logic [ROW_W-1:0]        nxt;

                col = col_of(j, dim_r);
                f   = (j == 0) ? aug[ei][k] : factor;
                if (j == 0) factor <= f;

                if (col == COL_W'(k)) begin
                    aug[ei][col] <= '0;
                end else begin
                    p = mulr(f, aug[k][col], s1);
                    d = subs(aug[ei][col], p, s2);
                    aug[ei][col] <= d;
                    if (s1 || s2) ovf <= 1'b1;
                end

                if (int'(j) == 2*int'(dim_r) - 1) begin
                    j   <= '0;
                    nxt = ei + 1'b1;
                    if (nxt == k) nxt = nxt + 1'b1;
                    if (nxt >= dim_r) next_column();
                    else              ei <= nxt;
                end else begin
                    j <= j + 1'b1;
                end
            end

            // ---------------------------------------------------------
            S_OUT: if (m_ready) begin
                if (m_last) begin
                    clear_aug();
                    state <= S_LOAD;
                end else if (out_col == dim_r - 1'b1) begin
                    out_col <= '0;
                    out_row <= out_row + 1'b1;
                end else begin
                    out_col <= out_col + 1'b1;
                end
            end

            default: state <= S_LOAD;
            endcase
        end
    end

endmodule
