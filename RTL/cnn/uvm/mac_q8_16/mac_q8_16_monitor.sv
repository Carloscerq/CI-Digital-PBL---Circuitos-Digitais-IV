// ---------------------------------------------------------------------
//  mac_q8_16_monitor  --  reconstructs job boundaries from the clr/en
//  handshake, the same idea as RTL/mac/uvm/mac_monitor.sv, but adapted
//  for mac_q8_16's extra pipeline stage: unlike mac.sv's `load`/`en`,
//  which the driver drops back to 0 at the end of a job (an unambiguous
//  "idle" marker), mac_q8_16_driver.sv never drops `en` -- it has to
//  stay high through the 3-cycle drain for the pipeline to actually
//  flush (see mac_q8_16_driver.sv's header comment). So there is no
//  "en==0" idle edge to key off of here.
//
//  Instead, a job's *start* is unambiguous: `clr && en` only ever
//  happens on a job's tap 0 (see the driver). This monitor uses that
//  same edge to also mark the *end* of whatever job was previously in
//  flight, and reads `vif.out` at that moment: because the driver always
//  holds a fixed 3-negedge drain (with a=b=0) after a job's last tap
//  before ever starting the next job's clr pulse, `out` is guaranteed
//  to have already been correct and stable for at least one extra
//  negedge by the time the next job's clr arrives (see mac_q8_16.sv's
//  pipeline: the last tap's contribution lands in acc_reg exactly 3
//  negedges after the tap's own negedge, i.e. by the drain's *last*
//  idle negedge -- one negedge before this trigger). So sampling
//  `vif.out` right here, before touching anything else this cycle, is
//  always the settled result of the job that just ended.
//
//  Every negedge with en==1 (real tap or drain-zero cycle alike) is
//  pushed into the running queue. The 3 trailing (a=0,b=0) drain entries
//  therefore end up appended to the reconstructed item's a[]/b[] arrays
//  too -- but since 0*0 contributes nothing to the sum, this is
//  numerically inert and the scoreboard's golden model (which recomputes
//  the sum straight from the item's own a[]/b[] arrays, not from
//  n_taps) is unaffected. It does mean the reconstructed item's n_taps
//  is a few taps larger than what the driving sequence originally
//  requested; that's expected and harmless here since this scoreboard
//  doesn't bucket coverage by tap count.
//
//  Because job N+1's clr is what retires job N, the very last job of a
//  test never gets a "next clr" to retire it against. extract_phase()
//  flushes any job still open at that point, reading vif.out one final
//  time -- by then simulation activity has quieted down (the driver's
//  forever loop is blocked waiting on the next item that never comes),
//  so `out` still holds that last job's already-settled result.
// ---------------------------------------------------------------------
class mac_q8_16_monitor #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_monitor;

    `uvm_component_param_utils(mac_q8_16_monitor #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS) vif;
    uvm_analysis_port #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)) ap;

    bit job_active;
    logic signed [DATA_WIDTH-1:0] a_q [$];
    logic signed [DATA_WIDTH-1:0] b_q [$];

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
        job_active = 1'b0;
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    function void flush_job(logic signed [DATA_WIDTH-1:0] settled_out);
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) item;
        item = mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("item");
        item.n_taps = a_q.size();
        item.a      = a_q;
        item.b      = b_q;
        item.out    = settled_out;
        ap.write(item);
        job_active = 1'b0;
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(negedge vif.clk);
            if (vif.clr && vif.en) begin
                if (job_active)
                    flush_job(vif.out);
                a_q.delete();
                b_q.delete();
                a_q.push_back(vif.a);
                b_q.push_back(vif.b);
                job_active = 1'b1;
            end else if (vif.en && job_active) begin
                a_q.push_back(vif.a);
                b_q.push_back(vif.b);
            end
        end
    endtask

    function void extract_phase(uvm_phase phase);
        super.extract_phase(phase);
        if (job_active)
            flush_job(vif.out);
    endfunction

endclass
