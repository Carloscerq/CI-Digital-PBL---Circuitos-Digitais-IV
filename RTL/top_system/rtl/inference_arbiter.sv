`timescale 1ns / 1ps

// ============================================================================
// Inference Arbiter
// ============================================================================
// Both models now produce a verdict for the WHOLE machine.
//
// >>> GLOBAL_MLP_NOTE <<<
// The MLP used to be time-multiplexed over the four vibration sensors, so its
// verdicts arrived tagged with `mlp_sensor_id` and were latched into per-sensor
// slots. The current model takes all four sensors in one 132-element vector
// (4 x 32 bins plus four aggregates), so there is no per-sensor attribution to
// make: `mlp_sensor_id` was constant zero and only bit 0 of the fault mask ever
// moved. The tag is gone and the MLP verdict is a single global bit.
//
// >>> FAULT_MASK_NOTE <<<
// `sensor_fault_mask` is kept as a port so the top-level pinout does not move,
// but its bits are no longer per-sensor: all N_SENSORS bits carry the same
// global MLP verdict. Restoring real per-sensor meaning would need a per-sensor
// source of evidence, which neither model provides today.
// ============================================================================
module inference_arbiter #(
    parameter int DATA_WIDTH = 24,
    parameter int N_SENSORS  = 4
)(
    input  logic clk,
    input  logic reset,

    // MLP: one result per round of the four sensors, global to the machine
    input  logic [1:0] mlp_class_idx,
    input  logic       mlp_done,

    // CNN: one result per spectrogram, all four sensors fused
    input  logic signed [DATA_WIDTH-1:0] cnn_normal,
    input  logic signed [DATA_WIDTH-1:0] cnn_unbalance,
    input  logic signed [DATA_WIDTH-1:0] cnn_misalign,
    input  logic signed [DATA_WIDTH-1:0] cnn_bearing,
    input  logic cnn_valid,

    // Outputs
    output logic [2:0]           status_leds,       // [2]=Critical [1]=Warning [0]=Normal
    output logic [N_SENSORS-1:0] sensor_fault_mask, // see FAULT_MASK_NOTE
    output logic                 alert_flag
);

    // ========================================================================
    // CNN argmax
    // ========================================================================
    // The classes map as follows, per mlp_weights.sv:
    // 0: Bearing, 1: Misalign, 2: Normal, 3: Unbalance
    logic [1:0] cnn_class_idx;

    always_comb begin
        logic signed [DATA_WIDTH-1:0] max_val;
        cnn_class_idx = 2'd2; // default to Normal
        max_val = cnn_normal;

        // Compare Bearing (0)
        if (cnn_bearing > max_val) begin
            max_val = cnn_bearing;
            cnn_class_idx = 2'd0;
        end
        // Compare Misalign (1)
        if (cnn_misalign > max_val) begin
            max_val = cnn_misalign;
            cnn_class_idx = 2'd1;
        end
        // Compare Unbalance (3)
        if (cnn_unbalance > max_val) begin
            max_val = cnn_unbalance;
            cnn_class_idx = 2'd3;
        end
    end

    // ========================================================================
    // Decision logic
    // ========================================================================
    // Classes 0 (Bearing), 1 (Misalign) and 3 (Unbalance) are FAULTS.
    // Class 2 is NORMAL.
    logic mlp_fault;
    logic cnn_fault;

    assign mlp_fault = (mlp_class_idx != 2'd2);
    assign cnn_fault = (cnn_class_idx != 2'd2);

    // Latch each verdict when its own pipeline produces one
    logic mlp_fault_reg;
    logic cnn_fault_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            mlp_fault_reg <= 1'b0;   // default normal
            cnn_fault_reg <= 1'b0;   // default normal
        end else begin
            if (mlp_done)  mlp_fault_reg <= mlp_fault;
            if (cnn_valid) cnn_fault_reg <= cnn_fault;
        end
    end

    assign sensor_fault_mask = {N_SENSORS{mlp_fault_reg}};

    always_comb begin
        // - NORMAL   : both models say Normal.
        // - WARNING  : the models disagree. An early warning for monitoring.
        // - CRITICAL : both models report a fault, so confidence is high.
        if (mlp_fault_reg && cnn_fault_reg) begin
            status_leds = 3'b100; // Critical (red)
            alert_flag  = 1'b1;
        end else if (mlp_fault_reg || cnn_fault_reg) begin
            status_leds = 3'b010; // Warning (yellow)
            alert_flag  = 1'b1;
        end else begin
            status_leds = 3'b001; // Normal (green)
            alert_flag  = 1'b0;
        end
    end

endmodule
