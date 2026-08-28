// ---------------------------------------------------------------------
//  spi_base_test    --  builds the env; parameterized so a concrete test
//                        only has to fix SIZE/N_SLAVES via inheritance.
//
//  spi_directed_test -- the SIZE=8, N_SLAVES=2 configuration driven by
//                        the top module: the six directed single-word
//                        exchanges, then 4 back-to-back random words,
//                        then a held 3-word transaction to slave 0.
// ---------------------------------------------------------------------
class spi_base_test #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_test;

    `uvm_component_param_utils(spi_base_test #(SIZE, N_SLAVES))

    spi_env #(SIZE, N_SLAVES) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = spi_env #(SIZE, N_SLAVES)::type_id::create("env", this);
    endfunction

endclass

class spi_directed_test extends spi_base_test #(8, 2);

    `uvm_component_utils(spi_directed_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        spi_directed_seq #(8, 2) dseq;
        spi_random_seq #(8, 2)   rseq;
        spi_hold_seq #(8, 2)     hseq;

        phase.raise_objection(this);

        dseq = spi_directed_seq #(8, 2)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        rseq = spi_random_seq #(8, 2)::type_id::create("rseq");
        rseq.num_txns = 4;
        rseq.start(env.agent.sequencer);

        hseq = spi_hold_seq #(8, 2)::type_id::create("hseq");
        hseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
