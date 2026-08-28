// ---------------------------------------------------------------------
//  preprocess_lms_fft_monitor  --  entirely passive with respect to the
//  DUT's protocol state (it drives only fft_ready, the standard
//  "monitor owns the randomized backpressure on the master side" shape
//  used by every downstream-facing UVM monitor in this repo, e.g.
//  smma_cnn_top_monitor/line_buffer_3x3_monitor/conv2d_fsm_monitor).
//  Three concurrent jobs:
//
//  (a) drive_backpressure() -- randomized ~75% fft_ready, toggled every
//      negedge ($urandom_range(0,3) != 0), matching the ~70-75%
//      backpressure style used across this repo's CNN UVM monitors
//      (e.g. dense_layer_fsm_monitor/line_buffer_3x3_monitor/
//      conv2d_fsm_monitor/maxpool_2x2_monitor all use exactly this
//      $urandom_range(0,3)!=0 formula).
//
//  (b) watch_beats() -- on every accepted fft_valid/fft_ready beat,
//      publishes a result item (fft_bin/fft_real/fft_imag) on `ap` for
//      preprocess_lms_fft_scoreboard.sv, which owns the per-beat
//      protocol checks (bin 0..63 contiguity per frame, X/Z-freedom --
//      see that file for why those checks live there and not here).
//
//  (c) watch_diagnostics() -- continuous, cycle-level interface
//      observation that doesn't naturally attach to any single fft
//      beat, so it's kept here rather than threaded through result
//      items:
//        - counts fft_done pulses (one per completed 64-bin frame);
//        - raises a `uvm_error` the moment any of the desired-side FIR
//          saturation events, the Hann-window saturation event, or the
//          FFT overflow event fires -- this testbench's stimulus
//          (preprocess_lms_fft_sequences.sv) is deliberately kept at
//          small, bounded amplitude specifically so that none of these
//          should ever fire; any that do are a real finding, not
//          silently tolerated;
//        - tracks whether pipeline_busy was EVER observed asserted
//          (busy_ever_seen) and its most recently observed value
//          (busy_last), for the loose liveness check
//          preprocess_lms_fft_test.sv performs after the stimulus
//          sequence finishes and a drain period has elapsed (busy_last
//          should have returned to 0 by then).
//
//  Deliberately NOT a bit-exact/golden-model checker: reimplementing
//  the FIR/decimation/windowing/FFT math here to check fft_real/
//  fft_imag values would duplicate the existing dataset-driven
//  verification path (RTL/FFT/model_sim_four_modes/verification/
//  tb_fft_lms_dataset.sv, which checks against an external
//  Python-computed golden reference) for no real extra confidence at
//  this stage -- see preprocess_lms_fft_scoreboard.sv for the full
//  scope rationale, mirroring the same call made for
//  RTL/cnn/uvm/smma_cnn_top/.
// ---------------------------------------------------------------------
class preprocess_lms_fft_monitor extends uvm_monitor;

    `uvm_component_utils(preprocess_lms_fft_monitor)

    virtual preprocess_lms_fft_if vif;
    uvm_analysis_port #(preprocess_lms_fft_seq_item) ap;

    int unsigned fft_done_count;
    bit          busy_ever_seen;
    bit          busy_last;

    int unsigned stage1_saturation_count;
    int unsigned stage2_saturation_count;
    int unsigned stage3_saturation_count;
    int unsigned hann_saturation_count;
    int unsigned fft_overflow_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual preprocess_lms_fft_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        fork
            drive_backpressure();
            watch_beats();
            watch_diagnostics();
        join
    endtask

    // --- (a) master-side randomized backpressure -----------------------
    task automatic drive_backpressure();
        vif.fft_ready = 1'b0;
        forever begin
            @(negedge vif.clk);
            vif.fft_ready = ($urandom_range(0, 3) != 0);
        end
    endtask

    // --- (b) accepted-beat capture, forwarded to the scoreboard ---------
    task automatic watch_beats();
        preprocess_lms_fft_seq_item item;
        forever begin
            @(posedge vif.clk);
            if (!vif.reset && vif.fft_valid && vif.fft_ready) begin
                item = preprocess_lms_fft_seq_item::type_id::create("item");
                item.fft_bin  = vif.fft_bin;
                item.fft_real = vif.fft_real;
                item.fft_imag = vif.fft_imag;
                ap.write(item);
            end
        end
    endtask

    // --- (c) continuous diagnostic/liveness observation -----------------
    task automatic watch_diagnostics();
        forever begin
            @(posedge vif.clk);
            if (!vif.reset) begin
                if (vif.desired_fir_stage1_saturation_event) begin
                    stage1_saturation_count++;
                    `uvm_error("SATURATION",
                        "desired_fir_stage1_saturation_event fired during benign small-amplitude stimulus")
                end
                if (vif.desired_fir_stage2_saturation_event) begin
                    stage2_saturation_count++;
                    `uvm_error("SATURATION",
                        "desired_fir_stage2_saturation_event fired during benign small-amplitude stimulus")
                end
                if (vif.desired_fir_stage3_saturation_event) begin
                    stage3_saturation_count++;
                    `uvm_error("SATURATION",
                        "desired_fir_stage3_saturation_event fired during benign small-amplitude stimulus")
                end
                if (vif.hann_saturation_event) begin
                    hann_saturation_count++;
                    `uvm_error("SATURATION",
                        "hann_saturation_event fired during benign small-amplitude stimulus")
                end
                if (vif.fft_overflow_event) begin
                    fft_overflow_count++;
                    `uvm_error("OVERFLOW",
                        $sformatf("fft_overflow_event fired (stage=%0d components=%0d) during benign small-amplitude stimulus",
                                  vif.fft_overflow_stage, vif.fft_overflow_components))
                end

                if (vif.fft_done)
                    fft_done_count++;

                if (vif.pipeline_busy)
                    busy_ever_seen = 1'b1;
                busy_last = vif.pipeline_busy;
            end
        end
    endtask

    function void report_phase(uvm_phase phase);
        `uvm_info("MONITOR",
            $sformatf("fft_done_count=%0d busy_ever_seen=%0b busy_last=%0b stage1_sat=%0d stage2_sat=%0d stage3_sat=%0d hann_sat=%0d fft_overflow=%0d",
                      fft_done_count, busy_ever_seen, busy_last,
                      stage1_saturation_count, stage2_saturation_count, stage3_saturation_count,
                      hann_saturation_count, fft_overflow_count), UVM_LOW)

        if (!busy_ever_seen)
            `uvm_error("BUSY", "pipeline_busy was never observed asserted during the run")
    endfunction

endclass
