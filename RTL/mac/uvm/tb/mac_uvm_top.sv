// ---------------------------------------------------------------------
//  mac_uvm_top  --  DUT + interface + UVM entry point for the wide
//                    configuration mlp.sv actually instantiates:
//                    DATA_WIDTH=24, WEIGHT_WIDTH=8, SUM_WIDTH=40 (see
//                    RTL/mlp_model/mlp.sv's
//                    `mac #(.DATA_WIDTH(ACT_WIDTH), .WEIGHT_WIDTH(W_WIDTH),
//                    .SUM_WIDTH(SUM_WIDTH))`). clk period and the reset
//                    sequencing mirror mac_tb.sv exactly (2ns period,
//                    two idle cycles held low before release).
//
//  No cfg object is needed: unlike perceptron, mac has no elaboration-
//  time parameters for the scoreboard to mirror.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module mac_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mac_pkg::*;

    localparam int DATA_WIDTH   = 24;
    localparam int WEIGHT_WIDTH = 8;
    localparam int SUM_WIDTH    = 40;
    localparam int MAX_TAPS     = 132;

    logic clk = 1'b0;
    always #1 clk = ~clk;   // matches mac_tb.sv's period

    mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH) vif (.clk(clk));

    mac #(
        .DATA_WIDTH  (DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .SUM_WIDTH   (SUM_WIDTH)
    ) dut (
        .clk    (vif.clk),
        .reset  (vif.reset),
        .load   (vif.load),
        .en     (vif.en),
        .data   (vif.data),
        .weight (vif.weight),
        .acc    (vif.acc)
    );

    initial begin
        vif.reset  = 1'b1;
        vif.load   = 1'b0;
        vif.en     = 1'b0;
        vif.data   = '0;
        vif.weight = '0;

        repeat (2) @(negedge clk);
        vif.reset = 1'b0;
        @(negedge clk);

        uvm_config_db #(virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        uvm_config_db #(virtual mac_if #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH))::set(
            null, "uvm_test_top", "vif", vif);

        run_test();
    end

endmodule
