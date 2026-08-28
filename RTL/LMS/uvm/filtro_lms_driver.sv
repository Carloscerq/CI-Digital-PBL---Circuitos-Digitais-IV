// ---------------------------------------------------------------------
//  filtro_lms_driver  --  single-beat ready/valid handshake, matching
//  tb_filtro_lms.v's own stimulus style exactly: wait for in_ready, drive
//  fft_re/fft_im + in_valid on one negedge, deassert in_valid on the
//  next negedge. `in_ready` is only ever asserted while the DUT is IDLE,
//  so there is no need to reason about the 11-state FSM latency here --
//  waiting for in_ready before every sample is sufficient.
//
//  Each driven item is published (in order, immediately after driving
//  it) on this driver's own analysis port `ap`, independent of whether
//  the DUT will ever produce a corresponding output -- the scoreboard's
//  shadow reference model needs to see every accepted sample, including
//  the very first one (which never produces output), to keep its
//  (w, x_prev, primeira_amostra) state in lockstep with the DUT. See
//  filtro_lms_scoreboard.sv.
// ---------------------------------------------------------------------
class filtro_lms_driver extends uvm_driver #(filtro_lms_seq_item);

    `uvm_component_utils(filtro_lms_driver)

    virtual filtro_lms_if vif;
    uvm_analysis_port #(filtro_lms_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual filtro_lms_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        filtro_lms_seq_item rsp;

        vif.in_valid = 1'b0;
        vif.fft_re   = '0;
        vif.fft_im   = '0;

        forever begin
            seq_item_port.get_next_item(req);

            wait (vif.in_ready === 1'b1);
            @(negedge vif.clk);
            vif.fft_re   = req.fft_re;
            vif.fft_im   = req.fft_im;
            vif.in_valid = 1'b1;
            @(negedge vif.clk);
            vif.in_valid = 1'b0;

            rsp = filtro_lms_seq_item::type_id::create("rsp");
            rsp.copy(req);
            ap.write(rsp);

            seq_item_port.item_done();
        end
    endtask

endclass
