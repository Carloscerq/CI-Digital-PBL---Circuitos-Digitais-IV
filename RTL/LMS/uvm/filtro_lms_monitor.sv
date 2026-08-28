// ---------------------------------------------------------------------
//  filtro_lms_monitor  --  passive: watches out_valid on posedge clk,
//  mirroring tb_filtro_lms.v's own `always @(posedge clk) if (out_valid)
//  ...` sampling style exactly. filt_re/filt_im are updated in the
//  DUT's ATUALIZA state via the same non-blocking assignment (in the
//  same always block) that also drives estado_atual to ENVIA (where
//  out_valid is asserted), so both update together at the posedge that
//  makes out_valid go high -- there is no extra settle cycle needed.
//
//  Publishes one "observed output" item per out_valid pulse, in arrival
//  order, via `ap`. This stream carries only got_output (always 1'b1 on
//  this stream) and filt_re/filt_im -- see filtro_lms_seq_item.sv.
// ---------------------------------------------------------------------
class filtro_lms_monitor extends uvm_monitor;

    `uvm_component_utils(filtro_lms_monitor)

    virtual filtro_lms_if vif;
    uvm_analysis_port #(filtro_lms_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual filtro_lms_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for monitor")
    endfunction

    task run_phase(uvm_phase phase);
        filtro_lms_seq_item item;

        forever begin
            @(posedge vif.clk);
            if (vif.out_valid) begin
                item = filtro_lms_seq_item::type_id::create("item");
                item.got_output = 1'b1;
                item.filt_re    = vif.filt_re;
                item.filt_im    = vif.filt_im;
                ap.write(item);
            end
        end
    endtask

endclass
