// ---------------------------------------------------------------------
//  filtro_lms_uvm_top  --  DUT + interface + UVM entry point, MU left at
//  its default (24'sd1638, matching filtro_lms_scoreboard.sv's shadow
//  golden model). clk period and reset sequencing mirror
//  tb_filtro_lms.v exactly: 10ns period (`forever #5 clk = ~clk`),
//  `reset` (active-high, synchronous -- see filtro_lms_if.sv) held high
//  for 30ns then released, with a further 20ns settle before stimulus
//  starts flowing (tb_filtro_lms.v's `reset=1; #30; reset=0; #20;`).
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
        vif.reset    = 1'b1;
        vif.in_valid = 1'b0;
        vif.fft_re   = 24'sd0;
        vif.fft_im   = 24'sd0;

        #30;
        vif.reset = 1'b0;
        #20;

        uvm_config_db #(virtual filtro_lms_if)::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        uvm_config_db #(virtual filtro_lms_if)::set(
            null, "uvm_test_top", "vif", vif);

        run_test();
    end

endmodule
