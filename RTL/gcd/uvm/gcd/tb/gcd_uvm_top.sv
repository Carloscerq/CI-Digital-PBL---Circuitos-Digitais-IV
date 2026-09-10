// ---------------------------------------------------------------------
//  gcd_uvm_top  --  DUT + interface + UVM entry point for the "full"
//                    array-reducing gcd configuration
//                    (AMOUNT_OF_NUMBERS=33, SIZE=32), the same config
//                    gcd_tb.sv's dut_full instance and random trials use.
//
//  Reset is NOT sequenced here: gcd_driver drives it from its UVM
//  reset_phase, so all interface timing lives inside the phase schedule
//  and the test's stimulus sits in main_phase, which cannot start
//  before reset_phase has finished. The pulse itself still mirrors
//  gcd_tb.sv exactly: reset starts low, then one negedge with reset
//  high, then one negedge with reset low again, before anything else
//  happens.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module gcd_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import gcd_pkg::*;

    localparam int AMOUNT_OF_NUMBERS = 33;
    localparam int SIZE              = 32;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    gcd_if #(AMOUNT_OF_NUMBERS, SIZE) vif (.clk(clk));

    gcd #(
        .AMOUNT_OF_NUMBERS(AMOUNT_OF_NUMBERS),
        .SIZE(SIZE)
    ) dut (
        .clk     (vif.clk),
        .reset (vif.reset),
        .start   (vif.start),
        .in      (vif.in),
        .out     (vif.out),
        .ready   (vif.ready)
    );

    initial begin
        uvm_config_db #(virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
