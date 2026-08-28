// ---------------------------------------------------------------------
//  gcd_base_test  --  builds the env. Parameterized so a concrete test
//                      only has to fix AMOUNT_OF_NUMBERS/SIZE via
//                      inheritance, mirroring perceptron_base_test.
//
//  gcd_full_random_test  --  the "full" configuration gcd_tb.sv also
//                             uses for its random trials
//                             (AMOUNT_OF_NUMBERS=33, SIZE=32): runs the
//                             9 directed corner cases first (see
//                             gcd_directed_seq), then a 50-trial
//                             constrained-random sweep (see
//                             gcd_random_seq), matching gcd_tb.sv's
//                             RANDOM_TRIALS.
// ---------------------------------------------------------------------
class gcd_base_test #(
    int AMOUNT_OF_NUMBERS = 33,
    int SIZE              = 32
) extends uvm_test;

    `uvm_component_param_utils(gcd_base_test #(AMOUNT_OF_NUMBERS, SIZE))

    gcd_env #(AMOUNT_OF_NUMBERS, SIZE) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = gcd_env #(AMOUNT_OF_NUMBERS, SIZE)::type_id::create("env", this);
    endfunction

endclass

class gcd_full_random_test extends gcd_base_test #(33, 32);

    `uvm_component_utils(gcd_full_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        gcd_directed_seq #(33, 32) dseq;
        gcd_random_seq   #(33, 32) rseq;

        phase.raise_objection(this);

        dseq = gcd_directed_seq #(33, 32)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = gcd_random_seq #(33, 32)::type_id::create("rseq");
        rseq.num_txns = 50;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
