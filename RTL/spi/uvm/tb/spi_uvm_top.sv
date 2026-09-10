// ---------------------------------------------------------------------
//  spi_uvm_top  --  DUT + interface + UVM entry point. Reproduces
//  spi_controller_tb.sv's topology exactly: one spi_controller plus a
//  generate loop of N_SLAVES=2 spi_slave instances on a shared bus
//  (slave 0: mode 0, CLK_DIV=4; slave 1: mode 3, CLK_DIV=6), with the
//  same combinational miso mux, clk generation, the CLK_DIV>=4 fatal
//  guard, and the safety-net timeout. Reset is NOT sequenced here: it
//  is an spi_if variable driven from spi_driver's UVM reset_phase, so
//  all interface timing stays inside the phase schedule.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module spi_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import spi_pkg::*;

    localparam int SIZE     = 8;
    localparam int N_SLAVES = 2;

    // slave 0: mode 0, fast.  slave 1: mode 3, slower. Same as
    // spi_controller_tb.sv.
    localparam int CLK_DIV [N_SLAVES] = '{4, 6};
    localparam bit CPOL    [N_SLAVES] = '{1'b0, 1'b1};
    localparam bit CPHA    [N_SLAVES] = '{1'b0, 1'b1};

    logic clk = 1'b0;

    always #5 clk = ~clk;

    // Below this the slave answers too late and the master reads the
    // previous bit on miso, so fail loudly instead of a puzzling mismatch.
    initial
        for (int s = 0; s < N_SLAVES; s++)
            if (CLK_DIV[s] < 4)
                $fatal(1, "spi_slave needs CLK_DIV >= 4, slave %0d has %0d",
                       s, CLK_DIV[s]);

    spi_if #(SIZE, N_SLAVES) vif (.clk(clk));

    spi_controller #(
        .SIZE(SIZE),
        .AMOUNT_OF_SLAVES(N_SLAVES),
        .CLK_DIV(CLK_DIV),
        .CPOL(CPOL),
        .CPHA(CPHA)
    ) controller (
        .clk(clk),
        .reset(vif.reset),
        .data_in(vif.data_in),
        .address(vif.address),
        .start(vif.start),
        .hold_select(vif.hold_select),
        .ready(vif.ready),
        .data_out(vif.data_out),
        .data_valid(vif.data_valid),
        .serial_clock(vif.serial_clock),
        .slave_in_controller_out(vif.mosi),
        .controller_in_slave_out(vif.miso),
        .slave_select_n(vif.slave_select_n)
    );

    logic slave_miso [N_SLAVES]; // each slave's own miso, muxed onto vif.miso below

    generate
        for (genvar s = 0; s < N_SLAVES; s++) begin : slaves
            spi_slave #(
                .SIZE(SIZE),
                .CPOL(CPOL[s]),
                .CPHA(CPHA[s])
            ) u_slave (
                .clk(clk),
                .reset(vif.reset),
                .data_in(vif.slave_data_in[s]),
                .data_out(vif.slave_data_out[s]),
                .data_valid(vif.slave_data_valid[s]),
                .busy(vif.slave_busy[s]),
                .serial_clock(vif.serial_clock),
                .slave_in_controller_out(vif.mosi),
                .controller_in_slave_out(slave_miso[s]),
                .slave_select_n(vif.slave_select_n[s])
            );
        end
    endgenerate

    // only the selected slave drives the shared miso line
    always_comb begin
        vif.miso = 1'b0;
        for (int s = 0; s < N_SLAVES; s++)
            if (!vif.slave_select_n[s]) vif.miso = slave_miso[s];
    end

    initial begin
        uvm_config_db #(virtual spi_if #(SIZE, N_SLAVES))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        run_test();
    end

    // safety net, a transfer takes about 2*SIZE*CLK_DIV clks
    initial begin
        #200000;
        `uvm_fatal("TIMEOUT", "the controller never raised data_valid")
    end

endmodule
