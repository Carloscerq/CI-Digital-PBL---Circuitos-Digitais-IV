// ---------------------------------------------------------------------
//  mac_base_test  --  builds the env; parameterized so a concrete test
//                      only has to fix the widths/MAX_TAPS via
//                      inheritance.
//
//  mac_wide_random_test  --  the config mlp.sv actually instantiates
//                             (DATA_WIDTH=24, WEIGHT_WIDTH=8,
//                             SUM_WIDTH=40, see RTL/mlp_model/mlp.sv's
//                             `mac #(.DATA_WIDTH(ACT_WIDTH), ...)`):
//                             runs the directed corner cases, the
//                             saturation-magnitude sweep, then the
//                             tap-count-bucketed random sweep.
//
//  mac_protocol_test  --  HOLD and SYNC_RESET aren't self-contained
//  "items" the way one dot-product job is (HOLD needs load=en=0 held
//  over several idle cycles while data/weight wiggle and acc must not
//  move; SYNC_RESET needs reset held across a posedge mid dot-product),
//  so this test grabs the raw virtual interface directly -- the same
//  way mac_tb.sv drives it -- and checks both behaviors with plain
//  procedural code instead of forcing them through the sequence/driver/
//  monitor/scoreboard item pipeline.
//
//  Stimulus runs in main_phase, not run_phase: reset is applied in
//  mac_driver's UVM reset_phase, and main_phase is the first
//  run-time phase guaranteed to start only after reset_phase has
//  dropped its objection -- run_phase spans the whole run-time
//  schedule, so it would have overlapped reset.
// ---------------------------------------------------------------------
class mac_base_test #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_test;

    `uvm_component_param_utils(mac_base_test #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    mac_env #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = mac_env #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("env", this);
    endfunction

endclass

class mac_wide_random_test extends mac_base_test #(24, 8, 40, 132);

    `uvm_component_utils(mac_wide_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task main_phase(uvm_phase phase);
        mac_directed_seq #(24, 8, 40, 132) dseq;
        mac_sat_seq #(24, 8, 40, 132)      sseq;
        mac_random_seq #(24, 8, 40, 132)   rseq;

        phase.raise_objection(this);

        dseq = mac_directed_seq #(24, 8, 40, 132)::type_id::create("dseq");
        dseq.start(env.agent.sequencer);

        sseq = mac_sat_seq #(24, 8, 40, 132)::type_id::create("sseq");
        sseq.start(env.agent.sequencer);

        rseq = mac_random_seq #(24, 8, 40, 132)::type_id::create("rseq");
        rseq.num_trials = 40;
        rseq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass

class mac_protocol_test extends uvm_test;

    `uvm_component_utils(mac_protocol_test)

    localparam int DATA_WIDTH   = 24;
    localparam int WEIGHT_WIDTH = 8;
    localparam int SUM_WIDTH    = 40;
    localparam int MAX_TAPS     = 132;

    virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH) vif;

    int unsigned check_count = 0;
    int unsigned error_count = 0;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for mac_protocol_test")
    endfunction

    task automatic do_check(string name, longint got, longint exp);
        check_count++;
        if (got !== exp) begin
            error_count++;
            `uvm_error("PROTOCOL", $sformatf("[%s] expected %0d, got %0d", name, exp, got))
        end
    endtask

    task main_phase(uvm_phase phase);
        phase.raise_objection(this);

        // ---- prime the accumulator with a known value ------------------
        @(negedge vif.clk);
        vif.data = DATA_WIDTH'(10); vif.weight = WEIGHT_WIDTH'(10);
        vif.load = 1'b1; vif.en = 1'b1;
        @(negedge vif.clk);
        vif.load = 1'b0; vif.en = 1'b0;
        do_check("PRIME", longint'(vif.acc), 100);

        // ---- HOLD: load=en=0 must leave acc untouched, even while ------
        // data/weight wiggle underneath it (mac_tb.sv's HOLD check)
        repeat (5) begin
            @(negedge vif.clk);
            vif.data   = DATA_WIDTH'(12345);
            vif.weight = WEIGHT_WIDTH'(77);
        end
        @(negedge vif.clk);
        do_check("HOLD", longint'(vif.acc), 100);

        // ---- LOAD_RESTART: load restarts a job without needing a reset -
        @(negedge vif.clk);
        vif.data = DATA_WIDTH'(11); vif.weight = WEIGHT_WIDTH'(11);
        vif.load = 1'b1; vif.en = 1'b1;
        @(negedge vif.clk);
        vif.load = 1'b0; vif.en = 1'b0;
        do_check("LOAD_RESTART", longint'(vif.acc), 121);

        // ---- SYNC_RESET: reset held across one posedge mid dot-product, -
        // which is what a synchronous reset needs to clear acc; it outranks
        // the load/en still being driven (mac_tb.sv's SYNC_RESET check)
        fork
            begin
                for (int i = 0; i < MAX_TAPS; i++) begin
                    @(negedge vif.clk);
                    vif.data   = DATA_WIDTH'($urandom);
                    vif.weight = WEIGHT_WIDTH'($urandom);
                    vif.load   = (i == 0);
                    vif.en     = 1'b1;
                end
                @(negedge vif.clk);
                vif.load = 1'b0;
                vif.en   = 1'b0;
            end
            begin
                repeat (20) @(negedge vif.clk);
                vif.reset = 1'b1;
                @(negedge vif.clk);   // the posedge in between clears acc
                do_check("SYNC_RESET", longint'(vif.acc), 0);
                vif.reset = 1'b0;
            end
        join

        `uvm_info("PROTOCOL_SUMMARY",
            $sformatf("checks=%0d errors=%0d", check_count, error_count), UVM_LOW)
        if (error_count != 0)
            `uvm_error("PROTOCOL_SUMMARY", $sformatf("%0d protocol errors", error_count))

        phase.drop_objection(this);
    endtask

endclass
