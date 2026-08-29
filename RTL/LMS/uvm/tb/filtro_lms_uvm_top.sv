// ---------------------------------------------------------------------
//  filtro_lms_uvm_top  --  DUT + interface + UVM entry point, MU left at
//  its default (24'sd1638, matching filtro_lms_scoreboard.sv's shadow
//  golden model). The clock period mirrors tb_filtro_lms.v exactly:
//  10ns (`forever #5 clk = ~clk`).
//
//  Reset is NOT sequenced here -- filtro_lms_driver drives it from its
//  UVM reset_phase, keeping all interface timing inside the phase
//  schedule and letting the test's stimulus sit in main_phase, which
//  cannot start before reset_phase has finished. The DUT still sees
//  tb_filtro_lms.v's sequence: `reset` (active-high, synchronous --
//  see filtro_lms_if.sv) held high for 3 cycles then released, with a
//  further 2 idle cycles before stimulus flows (tb_filtro_lms.v's
//  `reset=1; #30; reset=0; #20;`).
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module filtro_lms_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import filtro_lms_pkg::*;

    logic clk;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    filtro_lms_if vif (.clk(clk));

    filtro_lms #(
        .MU(24'sd1638)
    ) dut (
        .clk       (vif.clk),
        .reset     (vif.reset),
        .in_valid  (vif.in_valid),
        .fft_re    (vif.fft_re),
        .fft_im    (vif.fft_im),
        .in_ready  (vif.in_ready),
        .filt_re   (vif.filt_re),
        .filt_im   (vif.filt_im),
        .out_valid (vif.out_valid)
    );

    initial begin
        uvm_config_db #(virtual filtro_lms_if)::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        uvm_config_db #(virtual filtro_lms_if)::set(
            null, "uvm_test_top", "vif", vif);

        run_test();
    end

endmodule
