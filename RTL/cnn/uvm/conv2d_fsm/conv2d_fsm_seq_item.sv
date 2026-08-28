// ---------------------------------------------------------------------
//  conv2d_fsm_seq_item  --  one item is one 3x3xIN_CHANNELS window fed
//  to conv2d_fsm's slave stream, matching the DUT's `s_window` port
//  layout exactly ([channel][row][col]).
//
//  `is_last` is set by the sequence on the final window of a batch and
//  driven onto `s_last` by the driver; the DUT simply latches it as
//  `captured_last` and reflects it back on `m_last` once that window's
//  output beat fires, so this field also carries the *expected* m_last
//  value for the monitor's placement check.
//
//  `data_out` is not randomized: the monitor fills it in from `m_data`
//  once the matching output beat is observed, and that's the copy the
//  scoreboard checks against its golden model.
// ---------------------------------------------------------------------
class conv2d_fsm_seq_item extends uvm_sequence_item;

    localparam int DATA_WIDTH  = 24;
    localparam int CHANNELS    = 8;
    localparam int IN_CHANNELS = 4;

    rand logic signed [DATA_WIDTH-1:0] window [0:IN_CHANNELS-1][0:2][0:2];
    rand bit                           is_last;

    logic signed [DATA_WIDTH-1:0] data_out [0:CHANNELS-1];

    `uvm_object_utils(conv2d_fsm_seq_item)

    function new(string name = "conv2d_fsm_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        string s;
        s = $sformatf("is_last=%0b | data_out=[", is_last);
        foreach (data_out[i])
            s = {s, $sformatf("%0d%s", data_out[i], (i == CHANNELS-1) ? "" : ",")};
        return {s, "]"};
    endfunction

    function void do_copy(uvm_object rhs);
        conv2d_fsm_seq_item rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to conv2d_fsm_seq_item failed")
        super.do_copy(rhs);
        window   = rhs_.window;
        is_last  = rhs_.is_last;
        data_out = rhs_.data_out;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        conv2d_fsm_seq_item rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (window == rhs_.window) && (is_last == rhs_.is_last) &&
               (data_out == rhs_.data_out);
    endfunction

endclass
