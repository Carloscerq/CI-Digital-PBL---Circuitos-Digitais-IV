// ---------------------------------------------------------------------
//  mac_q8_16_uvm_top  --  DUT + interface + UVM entry point for the
//                    default configuration every CNN block instantiates
//                    mac_q8_16 with: DATA_WIDTH=24, FRAC_BITS=16. Clock
//                    period and reset sequencing mirror tb_mac_q8_16.sv
//                    exactly (100MHz / 10ns period, `reset=1; #20 reset=0;`).
//
//  mac_q8_16's reset is SYNCHRONOUS (`if (reset)` sampled on posedge clk
//  inside the DUT's always_ff), so `reset` is simply held high across a
//  couple of posedges and dropped.
//
//  No cfg object is needed: like RTL/mac/uvm, mac_q8_16 has no
//  elaboration-time parameters for the scoreboard to mirror.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module mac_q8_16_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mac_q8_16_pkg::*;

    localparam int DATA_WIDTH = 24;
    localparam int FRAC_BITS  = 16;
    localparam int MAX_TAPS   = 64;

    logic clk = 1'b0;
    always #5 clk = ~clk;   // matches tb_mac_q8_16.sv's 100MHz period

    mac_q8_16_if #(DATA_WIDTH, FRAC_BITS) vif (.clk(clk));

    mac_q8_16 #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS (FRAC_BITS)
    ) dut (
        .clk(vif.clk),
        .reset(vif.reset),
        .en (vif.en),
        .clr(vif.clr),
        .a  (vif.a),
        .b  (vif.b),
        .out(vif.out)
    );

    initial begin
        vif.reset = 1'b1;
        vif.en  = 1'b0;
        vif.clr = 1'b0;
        vif.a   = '0;
        vif.b   = '0;

        #20 vif.reset = 1'b0;
        @(negedge clk);

        uvm_config_db #(virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        uvm_config_db #(virtual mac_q8_16_if #(DATA_WIDTH, FRAC_BITS))::set(
            null, "uvm_test_top", "vif", vif);

        run_test();
    end

endmodule
