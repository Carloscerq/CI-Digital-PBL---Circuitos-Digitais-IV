// ---------------------------------------------------------------------
//  spi_seq_item  --  one word-exchange, covering both directions of the
//                     driver's stimulus and the monitor's observation.
//
//  The rand/intent fields are what a sequence picks and the driver's
//  exchange() bus-functional model actually drives onto the pins:
//  which slave gets addressed, the word the controller sends, the word
//  the addressed slave is preloaded to answer with, whether the select
//  stays down afterwards (hold), and -- only meaningful when hold is
//  set -- the word the slave should be reloaded with for the following
//  exchange (mirrors spi_controller_tb.sv's next_slave_word argument).
//
//  The obs_* fields are never touched by a sequence or the driver; the
//  monitor fills them in purely from DUT-visible pins/fabric signals
//  after reconstructing what a completed exchange actually did. Reusing
//  this same class for both streams keeps the scoreboard's field-by-
//  field comparison symmetric: expected.slave_word vs
//  observed.obs_master_side_word, expected.master_word vs
//  observed.obs_slave_side_word, and so on -- see spi_scoreboard.sv.
// ---------------------------------------------------------------------
class spi_seq_item #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_sequence_item;

    // -- intent, randomized by sequences, consumed by the driver --
    rand int unsigned     slave;
    rand logic [SIZE-1:0] master_word;
    rand logic [SIZE-1:0] slave_word;
    rand bit              hold;
         logic [SIZE-1:0] next_slave_word; // only used when hold == 1

    constraint c_slave_range { slave < N_SLAVES; }

    // -- observed, filled in by the monitor from DUT pins/fabric only --
    logic [SIZE-1:0] obs_master_side_word;  // controller's data_out
    logic [SIZE-1:0] obs_slave_side_word;   // addressed slave's data_out
    int              obs_slave;             // which slave select was seen down
    int              obs_word_counts[];     // per-slave word counters, size N_SLAVES
    bit              obs_select_idle_at_end; // slave_select_n fully released?

    `uvm_object_param_utils(spi_seq_item #(SIZE, N_SLAVES))

    function new(string name = "spi_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf(
            "slave=%0d master_word=%02h slave_word=%02h hold=%0b next_slave_word=%02h | obs_slave=%0d obs_master_side=%02h obs_slave_side=%02h obs_idle=%0b",
            slave, master_word, slave_word, hold, next_slave_word,
            obs_slave, obs_master_side_word, obs_slave_side_word, obs_select_idle_at_end);
    endfunction

    function void do_copy(uvm_object rhs);
        spi_seq_item #(SIZE, N_SLAVES) rhs_;
        if (!$cast(rhs_, rhs))
            `uvm_fatal("DO_COPY", "cast to spi_seq_item failed")
        super.do_copy(rhs);
        slave                   = rhs_.slave;
        master_word             = rhs_.master_word;
        slave_word              = rhs_.slave_word;
        hold                    = rhs_.hold;
        next_slave_word         = rhs_.next_slave_word;
        obs_master_side_word    = rhs_.obs_master_side_word;
        obs_slave_side_word     = rhs_.obs_slave_side_word;
        obs_slave               = rhs_.obs_slave;
        obs_word_counts         = rhs_.obs_word_counts;
        obs_select_idle_at_end  = rhs_.obs_select_idle_at_end;
    endfunction

    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        spi_seq_item #(SIZE, N_SLAVES) rhs_;
        if (!$cast(rhs_, rhs)) return 0;
        return (slave == rhs_.slave) && (master_word == rhs_.master_word) &&
               (slave_word == rhs_.slave_word) && (hold == rhs_.hold);
    endfunction

endclass
