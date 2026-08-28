`timescale 1ns / 1ps

// ============================================================================
// Inference Arbiter
// ============================================================================
// The MLP is time-multiplexed over the four vibration sensors, so its verdicts
// arrive one sensor at a time tagged with `mlp_sensor_id`; each is latched into
// its own slot. The CNN sees all four sensors at once (they are its four input
// channels), so it produces a single verdict for the machine.
// ============================================================================
module inference_arbiter #(
    parameter int DATA_WIDTH = 24,
    parameter int N_SENSORS  = 4
)(
    input  logic clk,
    input  logic reset_n,

    // MLP: one result per sensor frame
    input  logic [1:0] mlp_class_idx,
    input  logic [1:0] mlp_sensor_id,
    input  logic       mlp_done,

    // CNN: one result per spectrogram (all four sensors fused)
    input  logic signed [DATA_WIDTH-1:0] cnn_normal,
    input  logic signed [DATA_WIDTH-1:0] cnn_unbalance,
    input  logic signed [DATA_WIDTH-1:0] cnn_misalign,
    input  logic signed [DATA_WIDTH-1:0] cnn_bearing,
    input  logic cnn_valid,

    // Outputs
    output logic [2:0]           status_leds, // [2]=Critical, [1]=Warning, [0]=Normal
    output logic [N_SENSORS-1:0] sensor_fault_mask, // which sensor the MLP flagged
    output logic                 alert_flag
);

    // ========================================================================
    // CNN Argmax Logic
    // ========================================================================
    // The classes map to the following according to mlp_weights.sv:
    // 0: Bearing, 1: Misalign, 2: Normal, 3: Unbalance
    logic [1:0] cnn_class_idx;

    always_comb begin
        logic signed [DATA_WIDTH-1:0] max_val;
        cnn_class_idx = 2'd2; // Default to Normal
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
    // Decision Logic
    // ========================================================================
    // Classes: 0 (Bearing), 1 (Misalign), 3 (Unbalance) are FAULTS. 2 is NORMAL.
    logic mlp_fault;
    logic cnn_fault;

    assign mlp_fault = (mlp_class_idx != 2'd2);
    assign cnn_fault = (cnn_class_idx != 2'd2);

    // Latch the results when they become valid from their respective pipelines
    logic [N_SENSORS-1:0] mlp_fault_reg;
    logic                 cnn_fault_reg;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mlp_fault_reg <= '0;   // Default normal
            cnn_fault_reg <= 1'b0; // Default normal
        end else begin
            if (mlp_done) mlp_fault_reg[mlp_sensor_id] <= mlp_fault;
            if (cnn_valid) cnn_fault_reg <= cnn_fault;
        end
    end

    assign sensor_fault_mask = mlp_fault_reg;

    // Resolve the final state based on the latched inferences
    logic mlp_fault_any;
    assign mlp_fault_any = |mlp_fault_reg;

    always_comb begin
        // Comparison Logic Explanation:
        // - NORMAL: Both MLP and CNN must classify the system as Normal (No fault).
        // - WARNING: Disagreement between models (One detects a fault, the other doesn't).
        //            This acts as an early warning for monitoring.
        // - CRITICAL: Both models detect a fault, indicating high confidence in anomalous behavior.
        //
        // A fault on ANY of the four vibration sensors counts as an MLP fault:
        // the sensors watch different points of the same machine, so one bad
        // spectrum is enough. `sensor_fault_mask` says which one.

        if (mlp_fault_any && cnn_fault_reg) begin
            status_leds = 3'b100; // Critical (Red)
            alert_flag  = 1'b1;
        end else if (mlp_fault_any || cnn_fault_reg) begin
            status_leds = 3'b010; // Warning (Yellow)
            alert_flag  = 1'b1;
        end else begin
            status_leds = 3'b001; // Normal (Green)
            alert_flag  = 1'b0;
        end
    end

endmodule
