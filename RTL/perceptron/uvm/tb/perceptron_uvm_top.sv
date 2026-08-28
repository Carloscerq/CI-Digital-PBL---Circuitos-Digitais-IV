// ---------------------------------------------------------------------
//  perceptron_uvm_top  --  DUT + interface + UVM entry point for the
//                           layer-0 configuration: NUM_INPUTS=40,
//                           DATA_WIDTH=24, RELU=1, uniform weight=127,
//                           SCALE=883 (the same geometry
//                           perceptron_tb_fixedpoint.sv exercises by
//                           hand). `clk` paces the driver/monitor only;
//                           the DUT itself is combinational.
// ---------------------------------------------------------------------
`timescale 1ns/1ps

module perceptron_uvm_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import perceptron_pkg::*;

    localparam int NUM_INPUTS   = 40;
    localparam int DATA_WIDTH   = 24;
    localparam int WEIGHT_WIDTH = 8;
    localparam int SCALE_WIDTH  = 24;
    localparam int Q_FRAC       = 15;
    localparam bit RELU         = 1;

    localparam logic signed [WEIGHT_WIDTH-1:0] WEIGHTS [NUM_INPUTS] = '{default: 8'sd127};
    localparam logic signed [DATA_WIDTH-1:0]   BIAS  = 24'sd0;
    localparam logic signed [SCALE_WIDTH-1:0]  SCALE = 24'sd883;

    logic clk = 0;
    always #5 clk = ~clk;   // 10ns period; pacing only, DUT has no clock port

    perceptron_if #(NUM_INPUTS, DATA_WIDTH) vif (.clk(clk));

    perceptron #(
        .NUM_INPUTS  (NUM_INPUTS),
        .DATA_WIDTH  (DATA_WIDTH),
        .WEIGHT_WIDTH(WEIGHT_WIDTH),
        .SCALE_WIDTH (SCALE_WIDTH),
        .Q_FRAC      (Q_FRAC),
        .RELU        (RELU),
        .WEIGHTS     (WEIGHTS),
        .BIAS        (BIAS),
        .SCALE       (SCALE)
    ) dut (
        .inputs(vif.inputs),
        .out   (vif.out)
    );

    initial begin
        perceptron_cfg cfg;
        cfg = new("cfg");
        cfg.num_inputs = NUM_INPUTS;
        cfg.data_width = DATA_WIDTH;
        cfg.q_frac     = Q_FRAC;
        cfg.relu       = RELU;
        cfg.bias       = longint'(BIAS);
        cfg.scale      = longint'(SCALE);
        cfg.weights    = new[NUM_INPUTS];
        foreach (cfg.weights[i]) cfg.weights[i] = longint'(WEIGHTS[i]);

        uvm_config_db #(virtual perceptron_if #(NUM_INPUTS, DATA_WIDTH))::set(
            null, "uvm_test_top.env.agent.*", "vif", vif);
        uvm_config_db #(perceptron_cfg)::set(
            null, "uvm_test_top.env.scoreboard", "cfg", cfg);

        run_test();
    end

endmodule
