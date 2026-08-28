// ---------------------------------------------------------------------
//  gcd_uvm_top  --  DUT + interface + UVM entry point for the "full"
//                    array-reducing gcd configuration
//                    (AMOUNT_OF_NUMBERS=33, SIZE=32), the same config
//                    gcd_tb.sv's dut_full instance and random trials use.
//
//  Reset sequence mirrors gcd_tb.sv exactly: reset_n starts high, then
//  one negedge with reset_n low, then one negedge with reset_n high
//  again, before anything else happens.
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
        .reset_n (vif.reset_n),
        .start   (vif.start),
        .in      (vif.in),
        .out     (vif.out),
        .ready   (vif.ready)
    );

    initial begin
        vif.reset_n = 1'b1;
        vif.start   = 1'b0;

        @(negedge clk) vif.reset_n = 1'b0;
        @(negedge clk) vif.reset_n = 1'b1;

        uvm_config_db #(virtual gcd_if #(AMOUNT_OF_NUMBERS, SIZE))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
