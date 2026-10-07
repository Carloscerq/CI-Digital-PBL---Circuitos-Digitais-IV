// ---------------------------------------------------------------------
//  matrix_inv_base_test       --  builds the env; wait_drained() lets a
//                                 test end only once every matrix it
//                                 sent has been checked.
//
//  matrix_inv_directed_test   --  the directed cases only, with no idle
//                                 gaps and m_ready held high.
//
//  matrix_inv_random_test     --  default. Directed cases, then random
//                                 diagonally dominant, general and
//                                 small-integer matrices, with random
//                                 input gaps and output backpressure.
//
//  Stimulus runs in main_phase so it cannot overlap the reset the
//  driver applies in reset_phase.
// ---------------------------------------------------------------------
class matrix_inv_base_test extends uvm_test;

    `uvm_component_utils(matrix_inv_base_test)

    matrix_inv_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = matrix_inv_env::type_id::create("env", this);
    endfunction

    // the driver returns as soon as the last input beat is taken; the
    // result comes out a few hundred cycles later
    task wait_drained();
        fork
            wait (env.scoreboard.n_checked == env.agent.driver.n_driven);
            begin
                #1ms;
                `uvm_error("TIMEOUT", $sformatf("%0d of %0d matrices never came out",
                    env.agent.driver.n_driven - env.scoreboard.n_checked,
                    env.agent.driver.n_driven))
            end
        join_any
        disable fork;
    endtask

endclass

class matrix_inv_directed_test extends matrix_inv_base_test;

    `uvm_component_utils(matrix_inv_directed_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        matrix_inv_directed_seq dseq;

        phase.raise_objection(this);
        env.agent.driver.max_gap   = 0;
        env.agent.driver.ready_pct = 100;

        dseq = matrix_inv_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);
        wait_drained();
        phase.drop_objection(this);
    endtask

endclass

class matrix_inv_random_test extends matrix_inv_base_test;

    `uvm_component_utils(matrix_inv_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        matrix_inv_directed_seq dseq;
        matrix_inv_random_seq   rseq;
        matrix_inv_kind_e       kinds[3] = '{DIAG_DOMINANT, GENERAL, SMALL_INT};

        phase.raise_objection(this);

        dseq = matrix_inv_directed_seq::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        foreach (kinds[i]) begin
            rseq = matrix_inv_random_seq::type_id::create("rseq");
            rseq.kind       = kinds[i];
            rseq.num_trials = 200;
            rseq.start(env.agent.sequencer);
        end

        wait_drained();
        phase.drop_objection(this);
    endtask

endclass
