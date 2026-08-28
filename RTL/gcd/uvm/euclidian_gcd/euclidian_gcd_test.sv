// ---------------------------------------------------------------------
//  euclidian_gcd_base_test  --  builds the env; parameterized so a
//                                concrete test only has to fix SIZE via
//                                inheritance, mirroring mac_base_test.
//
//  euclidian_gcd_random_test  --  the config gcd.sv actually instantiates
//                                  euclidian_gcd at (SIZE=32, see
//                                  RTL/gcd/gcd.sv's
//                                  `euclidian_gcd #(.SIZE(SIZE)) pair_gcd`
//                                  with the top-level's own testbench
//                                  using SIZE=32): runs the directed
//                                  corner cases, then a bounded-magnitude
//                                  random sweep.
// ---------------------------------------------------------------------
class euclidian_gcd_base_test #(
    int SIZE = 32
) extends uvm_test;

    `uvm_component_param_utils(euclidian_gcd_base_test #(SIZE))

    euclidian_gcd_env #(SIZE) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = euclidian_gcd_env #(SIZE)::type_id::create("env", this);
    endfunction

endclass

class euclidian_gcd_random_test extends euclidian_gcd_base_test #(32);

    `uvm_component_utils(euclidian_gcd_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        euclidian_gcd_directed_seq #(32) dseq;
        euclidian_gcd_random_seq #(32)   rseq;

        phase.raise_objection(this);

        dseq = euclidian_gcd_directed_seq #(32)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = euclidian_gcd_random_seq #(32)::type_id::create("rseq");
        rseq.num_trials = 80;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
