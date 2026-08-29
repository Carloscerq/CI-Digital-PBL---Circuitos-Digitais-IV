// ---------------------------------------------------------------------
//  spi_driver  --  a bus-functional model, not a fixed "apply on this
//                   edge" driver: SPI's per-item latency is variable and
//                   slave-dependent (wait for busy, wait for data_valid),
//                   so exchange() below ports spi_controller_tb.sv's
//                   exchange() task almost verbatim against the virtual
//                   interface. This is standard UVM practice for
//                   data/ready handshaking protocols.
//
//  After each item completes, a copy carrying only the intent fields
//  (slave/master_word/slave_word/hold) is published on this driver's own
//  analysis port `ap`, so the scoreboard can pair it against the
//  monitor's independently-reconstructed observed item -- see
//  spi_scoreboard.sv.
// ---------------------------------------------------------------------
class spi_driver #(
    int SIZE     = 8,
    int N_SLAVES = 2
) extends uvm_driver #(spi_seq_item #(SIZE, N_SLAVES));

    `uvm_component_param_utils(spi_driver #(SIZE, N_SLAVES))

    localparam int ADDR_W = (N_SLAVES > 1) ? $clog2(N_SLAVES) : 1;

    virtual spi_if #(SIZE, N_SLAVES) vif;
    uvm_analysis_port #(spi_seq_item #(SIZE, N_SLAVES)) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spi_if #(SIZE, N_SLAVES))::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        spi_seq_item #(SIZE, N_SLAVES) rsp;

        // idle bus state, matching spi_controller_tb.sv's reset-time defaults
        vif.data_in     = '0;
        vif.address     = '0;
        vif.start       = 1'b0;
        vif.hold_select = 1'b0;
        for (int s = 0; s < N_SLAVES; s++) vif.slave_data_in[s] = '0;

        wait (vif.reset === 1'b0);

        forever begin
            seq_item_port.get_next_item(req);
            exchange(req);

            rsp = spi_seq_item #(SIZE, N_SLAVES)::type_id::create("rsp");
            rsp.copy(req);
            ap.write(rsp);

            seq_item_port.item_done();
        end
    endtask

    // One full duplex exchange with the given item's slave, ported
    // directly from spi_controller_tb.sv's exchange() task.
    task automatic exchange(spi_seq_item #(SIZE, N_SLAVES) item);
        @(negedge vif.clk);
        // the slave latches data_in when its select falls, so it has to be
        // up before the transfer starts
        vif.slave_data_in[item.slave] = item.slave_word;

        if (vif.ready !== 1'b1)
            `uvm_error("DRV", "controller not ready before start")

        vif.data_in     = item.master_word;
        vif.address     = ADDR_W'(item.slave);
        vif.start       = 1'b1;
        vif.hold_select = item.hold;
        @(negedge vif.clk);
        vif.start       = 1'b0;
        vif.hold_select = 1'b0;

        // The slave reloads its transmit register the moment a word
        // completes, so the answer for a following word has to be up well
        // before that. Wait for it to have taken this word first.
        if (item.hold) begin
            do @(negedge vif.clk); while (!vif.slave_busy[item.slave]);
            repeat (2) @(negedge vif.clk); // busy leads the load by a cycle
            vif.slave_data_in[item.slave] = item.next_slave_word;
        end

        // data_valid pulses for one clk with the received word on data_out
        do @(negedge vif.clk); while (!vif.data_valid);
        // let the slave side settle, it runs a few clks behind the pins
        repeat (2) @(negedge vif.clk);
    endtask

endclass
