// ---------------------------------------------------------------------
//  mlp_uvm_top  --  DUT + interface + UVM entry point for the mlp
//                    inference engine. There's exactly one valid
//                    geometry here (tied to the trained weights in
//                    mlp_weights.sv), so no elaboration-time cfg object
//                    is needed -- unlike perceptron_uvm_top, nothing
//                    about the DUT instance varies from run to run.
//
//  Reset sequence mirrors mlp_tb_dpi.sv exactly: 4 negedges with
//  reset high, then reset low, then 2 more negedges before anything
//  else happens.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module mlp_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import mlp_pkg::*;

    logic clk = 1'b0;
    always #1 clk = ~clk;

    mlp_if vif (.clk(clk));

    mlp dut (
        .clk       (vif.clk),
        .reset     (vif.reset),
        .start     (vif.start),
        .features  (vif.features),
        .logits    (vif.logits),
        .class_idx (vif.class_idx),
        .busy      (vif.busy),
        .done      (vif.done)
    );

    initial begin
        vif.reset = 1'b1;
        vif.start = 1'b0;

        repeat (4) @(negedge clk);
        vif.reset = 1'b0;
        repeat (2) @(negedge clk);

        uvm_config_db #(virtual mlp_if)::set(null, "uvm_test_top.env.agent.*", "vif", vif);

        run_test();
    end

endmodule
