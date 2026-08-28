// ---------------------------------------------------------------------
//  mac_q8_16_base_test  --  builds the env; parameterized so a concrete
//                     test only has to fix the widths/MAX_TAPS via
//                     inheritance.
//
//  mac_q8_16_default_test  --  the config every CNN block instantiates
//                     mac_q8_16 with (DATA_WIDTH=24, FRAC_BITS=16): runs
//                     the directed corner cases ported from
//                     tb_mac_q8_16.sv, then the saturation-magnitude
//                     sweep, then the tap-count-swept random sequence.
// ---------------------------------------------------------------------
class mac_q8_16_base_test #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_test;

    `uvm_component_param_utils(mac_q8_16_base_test #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    mac_q8_16_env #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mac_q8_16_env #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("env", this);
    endfunction

endclass

class mac_q8_16_default_test extends mac_q8_16_base_test #(24, 16, 64);

    `uvm_component_utils(mac_q8_16_default_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        mac_q8_16_directed_seq #(24, 16, 64) dseq;
        mac_q8_16_sat_seq #(24, 16, 64)      sseq;
        mac_q8_16_random_seq #(24, 16, 64)   rseq;

        phase.raise_objection(this);

        dseq = mac_q8_16_directed_seq #(24, 16, 64)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        sseq = mac_q8_16_sat_seq #(24, 16, 64)::type_id::create("sseq");
        sseq.start(env.agent.sequencer);

        rseq = mac_q8_16_random_seq #(24, 16, 64)::type_id::create("rseq");
        rseq.num_trials = 40;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass
