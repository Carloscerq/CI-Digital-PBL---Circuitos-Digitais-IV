// ---------------------------------------------------------------------
//  matrix_inv_base_seq     --  send() helper shared by the others.
//
//  matrix_inv_directed_seq --  the same directed cases as
//      matrix_inv_tb.sv: identity at every size, matrices with exact
//      inverses, zero/small/tied leading pivots (row swaps), singular
//      matrices (pivot below PIVOT_EPS), results that overflow Q9.15,
//      s_dim = 0, and early / missing s_last.
//
//  matrix_inv_random_seq   --  num_trials random matrices of one kind:
//      DIAG_DOMINANT  well conditioned; the scoreboard also holds these
//                     to the precision tolerance against double
//      GENERAL        uniform entries in [-8, 8): any conditioning,
//                     bit-exact check only
//      SMALL_INT      integers in [-3, 3]: many tied pivot candidates
//                     and many singular matrices
// ---------------------------------------------------------------------
class matrix_inv_base_seq extends uvm_sequence #(matrix_inv_seq_item);

    `uvm_object_utils(matrix_inv_base_seq)

    function new(string name = "matrix_inv_base_seq");
        super.new(name);
    endfunction

    task send(input int dim, input mat_t a, input int dim_field = -1, input int last_at = -1);
        matrix_inv_seq_item item;
        item = matrix_inv_seq_item::type_id::create("item");
        start_item(item);
        item.dim       = dim;
        item.a         = a;
        item.dim_field = (dim_field < 0) ? dim : dim_field;
        item.last_at   = (last_at < 0) ? dim*dim - 1 : last_at;
        finish_item(item);
    endtask

endclass

class matrix_inv_directed_seq extends matrix_inv_base_seq;

    `uvm_object_utils(matrix_inv_directed_seq)

    function new(string name = "matrix_inv_directed_seq");
        super.new(name);
    endfunction

    task body();
        mat_t a;
        real  eps;

        eps = real'(PIVOT_EPS) * LSB;

        for (int n = 1; n <= N_MAX; n++) begin
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++)
                    a[r][c] = (r == c && r < n) ? to_q(1.0) : 0;
            send(n, a);
        end

        // exact inverses
        send(1, mk(1, "-0.25"));
        send(4, mk(4, "2 0 0 0  0 -4 0 0  0 0 0.5 0  0 0 0 8"));
        send(2, mk(2, "4 7  2 6"));
        send(3, mk(3, "2 -1 0  -1 2 -1  0 -1 2"));
        send(4, mk(4, "1 0 0 0  1 1 0 0  1 1 1 0  1 1 1 1"));
        send(4, mk(4, "4 -2 1 3  3 6 -4 2  2 1 8 -5  1 3 -2 7"));

        // pivoting
        send(2, mk(2, "0 1  1 0"));
        send(3, mk(3, "0 0 1  1 0 0  0 1 0"));
        send(4, mk(4, "0 2 1 0  1 0 0 3  0 1 0 1  2 0 1 0"));
        send(3, mk(3, "0.001 1 2  1 3 1  2 1 4"));
        send(3, mk(3, "3 1 2  -3 2 1  3 5 7"));
        send(3, mk(3, "-5 1 0  1 -3 1  0 1 -4"));

        // singular
        send(2, mk(2, "1 2  2 4"));
        send(3, mk(3, "1 2 3  0 0 0  4 5 6"));
        send(4, mk(4, "1 2 3 4  2 0 1 1  3 2 4 5  0 1 1 2"));
        send(4, mk(4, ""));
        send(2, mk(2, $sformatf("1 0  0 %.10f", eps/2)));

        // overflow
        send(2, mk(2, $sformatf("1 0  0 %.10f", eps*2)));
        send(2, mk(2, "1 1  1 1.00390625"));
        send(1, mk(1, "0.003"));

        // s_dim = 0 -> N_MAX
        send(4, mk(4, "2 0 0 0  0 2 0 0  0 0 2 0  0 0 0 2"), 0);

        // framing
        send(3, mk(3, "1 2 3  4 5 6  7 8 10"), -1, 4);
        send(2, mk(2, "3 1  1 2"), -1, 100);
        send(2, mk(2, "3 1  1 2"));
    endtask

endclass

typedef enum { DIAG_DOMINANT, GENERAL, SMALL_INT } matrix_inv_kind_e;

class matrix_inv_random_seq extends matrix_inv_base_seq;

    `uvm_object_utils(matrix_inv_random_seq)

    matrix_inv_kind_e kind       = DIAG_DOMINANT;
    int unsigned      num_trials = 200;

    function new(string name = "matrix_inv_random_seq");
        super.new(name);
    endfunction

    task body();
        mat_t a;
        int   dim;
        real  s, d;

        repeat (num_trials) begin
            dim = (kind == SMALL_INT) ? $urandom_range(N_MAX, 2) : $urandom_range(N_MAX, 1);
            for (int r = 0; r < N_MAX; r++)
                for (int c = 0; c < N_MAX; c++)
                    a[r][c] = 0;

            case (kind)
            DIAG_DOMINANT:
                for (int r = 0; r < dim; r++) begin
                    s = 0.0;
                    for (int c = 0; c < dim; c++) begin
                        if (c == r) continue;
                        a[r][c] = $urandom_range(2*to_q(2.0)) - to_q(2.0);
                        s += (a[r][c] < 0) ? -from_q(a[r][c]) : from_q(a[r][c]);
                    end
                    d = s + 0.5 + from_q($urandom_range(to_q(4.0)));
                    a[r][r] = $urandom_range(1) ? to_q(d) : -to_q(d);
                end
            GENERAL:
                for (int r = 0; r < dim; r++)
                    for (int c = 0; c < dim; c++)
                        a[r][c] = $urandom_range(2*to_q(8.0)) - to_q(8.0);
            SMALL_INT:
                for (int r = 0; r < dim; r++)
                    for (int c = 0; c < dim; c++)
                        a[r][c] = to_q(real'($urandom_range(6)) - 3.0);
            endcase

            send(dim, a);
        end
    endtask

endclass
