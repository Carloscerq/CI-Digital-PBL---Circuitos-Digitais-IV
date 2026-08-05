`timescale 1ns / 1ps

module smma_cnn_top (
    input  logic               clk,
    input  logic               rst,
    
    // AXI4-Stream Slave Interface (Input Spectrogram)
    input  logic               s_axis_valid,
    output logic               s_axis_ready,
    input  logic signed [23:0] s_axis_data,
    input  logic               s_axis_last,
    
    // AXI4-Stream Master Interface (Output Classification Logits)
    output logic               m_axis_valid,
    input  logic               m_axis_ready,
    output logic signed [23:0] m_axis_data_normal,
    output logic signed [23:0] m_axis_data_unbalance,
    output logic signed [23:0] m_axis_data_misalign,
    output logic signed [23:0] m_axis_data_bearing,
    output logic               m_axis_last
);

    // =========================================================================
    // Interconnect Signals
    // =========================================================================

    // Line Buffer to Conv2D
    logic               lb_valid;
    logic               lb_ready;
    logic signed [23:0] lb_window [0:2][0:2];
    logic               lb_last;

    // Conv2D to MaxPool
    logic               conv_valid;
    logic               conv_ready;
    logic signed [23:0] conv_data [0:7];
    logic               conv_last;

    // MaxPool to Dense
    logic               pool_valid;
    logic               pool_ready;
    logic signed [23:0] pool_data [0:7];
    logic               pool_last;

    // Dense Output
    logic               dense_valid;
    logic               dense_ready;
    logic signed [23:0] dense_data [0:3];
    logic               dense_last;

    // =========================================================================
    // Module Instantiations
    // =========================================================================

    // 1. Line Buffer (3x3 Window Generation with Padding)
    // Absorbs the incoming 1D pixel stream and outputs a sliding 3x3 window in parallel.
    // Handles zero-padding (Padding=1) mathematically without downstream overhead.
    line_buffer_3x3 inst_line_buffer (
        .clk     (clk),
        .rst     (rst),
        .s_valid (s_axis_valid),
        .s_ready (s_axis_ready),
        .s_data  (s_axis_data),
        .s_last  (s_axis_last),
        .m_valid (lb_valid),
        .m_ready (lb_ready),
        .m_window(lb_window),
        .m_last  (lb_last)
    );

    // 2. Conv2D FSM (8 Parallel Filters, ReLU Activation)
    // Instantiates exactly 8 DSP-based MACs. Time-multiplexes the 9 window pixels
    // and bias over 10 clock cycles. Applies combinatorial ReLU at the output.
    conv2d_fsm inst_conv2d (
        .clk     (clk),
        .rst     (rst),
        .s_valid (lb_valid),
        .s_ready (lb_ready),
        .s_window(lb_window),
        .s_last  (lb_last),
        .m_valid (conv_valid),
        .m_ready (conv_ready),
        .m_data  (conv_data),
        .m_last  (conv_last)
    );

    // 3. MaxPool 2x2 (Stride 2 Downsampling)
    // Utilizes optimized SRL delay lines to extract non-overlapping 2x2 grids 
    // from the 8-channel stream and calculates the cascaded maximum.
    maxpool_2x2 inst_maxpool (
        .clk     (clk),
        .rst     (rst),
        .s_valid (conv_valid),
        .s_ready (conv_ready),
        .s_data  (conv_data),
        .s_last  (conv_last),
        .m_valid (pool_valid),
        .m_ready (pool_ready),
        .m_data  (pool_data),
        .m_last  (pool_last)
    );

    // 4. Dense Layer FSM (On-the-fly 2048x4 Matrix Multiplication)
    // Uses 4 parallel DSPs and 4 M10K BRAM ROMs to compute the final 4 logits
    // concurrently as elements arrive, avoiding heavy full-frame BRAM buffers.
    dense_layer_fsm inst_dense (
        .clk     (clk),
        .rst     (rst),
        .s_valid (pool_valid),
        .s_ready (pool_ready),
        .s_data  (pool_data),
        .s_last  (pool_last),
        .m_valid (dense_valid),
        .m_ready (dense_ready),
        .m_data  (dense_data),
        .m_last  (dense_last)
    );

    // =========================================================================
    // Output Assignments
    // =========================================================================
    
    // Connect the dense layer output directly to the AXI4-Stream master ports
    assign m_axis_valid          = dense_valid;
    assign dense_ready           = m_axis_ready;
    assign m_axis_last           = dense_last;

    // Map the 4 internal array elements to the explicitly named flat top-level ports
    assign m_axis_data_normal    = dense_data[0];
    assign m_axis_data_unbalance = dense_data[1];
    assign m_axis_data_misalign  = dense_data[2];
    assign m_axis_data_bearing   = dense_data[3];

endmodule
