// ---------------------------------------------------------------------
//  euclidian_gcd_uvm_top  --  DUT + interface + UVM entry point for the
//                              pairwise GCD block, at the SIZE=32
//                              configuration gcd.sv actually instantiates
//                              it at (see RTL/gcd/gcd.sv's
//                              `euclidian_gcd #(.SIZE(SIZE)) pair_gcd`,
//                              with the top-level's own testbench using
//                              SIZE=32).
//
//  The clk period mirrors euclidian_gcd_tb.sv exactly (10ns). Reset is
//  NOT sequenced here: euclidian_gcd_driver drives it from its UVM
//  reset_phase, so all interface timing lives inside the phase schedule
//  and the test's stimulus sits in main_phase, which cannot start
//  before reset_phase has finished. The pulse itself is unchanged --
//  euclidian_gcd_tb.sv's reset starts low, then one negedge high, one
//  negedge low.
//
//  No cfg object is needed: like mac, euclidian_gcd has no elaboration-
//  time parameters for the scoreboard to mirror.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module euclidian_gcd_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import euclidian_gcd_pkg::*;

    localparam int SIZE = 32;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // matches euclidian_gcd_tb.sv's period

    euclidian_gcd_if #(SIZE) vif (.clk(clk));

    euclidian_gcd #(.SIZE(SIZE)) dut (
        .clk     (vif.clk),
        .reset (vif.reset),
        .start   (vif.start),
        .in_a    (vif.in_a),
        .in_b    (vif.in_b),
        .out     (vif.out),
        .ready   (vif.ready)
    );

    initial begin
        uvm_config_db #(virtual euclidian_gcd_if #(SIZE))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
