// ---------------------------------------------------------------------
//  matrix_inv_seq_item  --  one matrix through the DUT.
//
//  Stimulus fields (set by sequences, driven by the driver):
//    dim        matrix size, 1..N_MAX
//    dim_field  value put on s_dim (normally dim; 0 checks the
//               "0 means N_MAX" rule)
//    last_at    beat index that carries s_last (dim*dim-1 is a correct
//               frame; smaller ends the frame early; >= dim*dim never
//               asserts it)
//    a          the matrix, raw Q9.15, row-major in [0..dim-1][0..dim-1]
//
//  Observed fields (filled by the monitor from the pins, never from the
//  stimulus fields, so the scoreboard checks what really happened):
//    obs_dim, a_loaded, last_seen_at  what the DUT was given
//    inv, n_out, last_ok, singular, overflow, frame_err, cycles
//                                    what it gave back
//
//  The matrices are filled procedurally by the sequences rather than by
//  randomize(): the interesting cases (diagonally dominant, small
//  integers, singular) are easier to build directly than to constrain.
// ---------------------------------------------------------------------
class matrix_inv_seq_item extends uvm_sequence_item;

    // stimulus
    int   dim       = N_MAX;
    int   dim_field = -1;
    int   last_at   = -1;
    mat_t a;

    // observed
    int   obs_dim;
    mat_t a_loaded;
    int   last_seen_at;
    mat_t inv;
    int   n_out;
    bit   last_ok;
    bit   singular;
    bit   overflow;
    bit   frame_err;
    int   cycles;

    `uvm_object_utils(matrix_inv_seq_item)

    function new(string name = "matrix_inv_seq_item");
        super.new(name);
    endfunction

    function string mat2string(input int n, input mat_t m);
        string s = "";
        for (int r = 0; r < n; r++) begin
            s = {s, "["};
            for (int c = 0; c < n; c++)
                s = {s, $sformatf(" %9.5f", from_q(m[r][c]))};
            s = {s, " ]"};
        end
        return s;
    endfunction

    function string convert2string();
        return $sformatf("dim=%0d A=%s inv=%s singular=%0b overflow=%0b frame_err=%0b cycles=%0d",
                         obs_dim, mat2string(obs_dim, a_loaded), mat2string(obs_dim, inv),
                         singular, overflow, frame_err, cycles);
    endfunction

    function void do_copy(uvm_object rhs);
        matrix_inv_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to matrix_inv_seq_item failed")
        super.do_copy(rhs);
        dim          = rhs_.dim;
        dim_field    = rhs_.dim_field;
        last_at      = rhs_.last_at;
        a            = rhs_.a;
        obs_dim      = rhs_.obs_dim;
        a_loaded     = rhs_.a_loaded;
        last_seen_at = rhs_.last_seen_at;
        inv          = rhs_.inv;
        n_out        = rhs_.n_out;
        last_ok      = rhs_.last_ok;
        singular     = rhs_.singular;
        overflow     = rhs_.overflow;
        frame_err    = rhs_.frame_err;
        cycles       = rhs_.cycles;
    endfunction

endclass
