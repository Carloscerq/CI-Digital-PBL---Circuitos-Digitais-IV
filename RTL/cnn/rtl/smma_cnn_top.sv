`timescale 1ns / 1ps

// ============================================================================
// SMMA CNN top
// ============================================================================
// Stream handshake used on every port here and throughout the CNN: a beat
// transfers when valid and ready are both high on a rising clock edge, and
// `last` marks the final beat of an image. Data, valid, ready and last are the
// only signals -- there is no sideband (keep/strobe/id/user), no address phase
// and no bursts.
// ============================================================================
module smma_cnn_top #(
    parameter int DATA_WIDTH = 24,
    parameter int FRAC_BITS = 16,
    parameter int IMG_WIDTH = 32,
    parameter int IMG_HEIGHT = 32,
    parameter int IN_CHANNELS = 4,   // 4 physical sensors
    parameter int CHANNELS = 8,
    parameter int OUT_CLASSES = 4,
    parameter int IN_FEATURES = 2048
)(
    input  logic clk,
    input  logic reset,
    
    // Stream slave: one pixel per channel per beat
    input  logic s_valid,
    output logic s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data [0:IN_CHANNELS-1],
    input  logic s_last,
    
    // Stream master: one logit set per image, to the decision logic
    output logic m_valid,
    input  logic m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data_normal,
    output logic signed [DATA_WIDTH-1:0] m_data_unbalance,
    output logic signed [DATA_WIDTH-1:0] m_data_misalign,
    output logic signed [DATA_WIDTH-1:0] m_data_bearing,
    output logic m_last
);

    // ==========================================
    // Interconnect 1: Line Buffer to Conv2D
    // ==========================================
    logic        lb_valid;
    logic        lb_ready;
    logic signed [DATA_WIDTH-1:0] lb_window [0:IN_CHANNELS-1][0:2][0:2];
    logic        lb_last;
    
    line_buffer_3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT),
        .IN_CHANNELS(IN_CHANNELS)
    ) u_line_buffer (
        .clk(clk),
        .reset(reset),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .s_last(s_last),
        .m_valid(lb_valid),
        .m_ready(lb_ready),
        .m_window(lb_window),
        .m_last(lb_last)
    );

    // ==========================================
    // Interconnect 2: Conv2D to MaxPool
    // ==========================================
    logic        conv_valid;
    logic        conv_ready;
    logic signed [DATA_WIDTH-1:0] conv_data [0:CHANNELS-1];
    logic        conv_last;

    conv2d_fsm #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS(FRAC_BITS),
        .CHANNELS(CHANNELS),
        .IN_CHANNELS(IN_CHANNELS)
    ) u_conv2d (
        .clk(clk),
        .reset(reset),
        .s_valid(lb_valid),
        .s_ready(lb_ready),
        .s_window(lb_window),
        .s_last(lb_last),
        .m_valid(conv_valid),
        .m_ready(conv_ready),
        .m_data(conv_data),
        .m_last(conv_last)
    );

    // ==========================================
    // Interconnect 3: MaxPool to Dense Layer
    // ==========================================
    logic        pool_valid;
    logic        pool_ready;
    logic signed [DATA_WIDTH-1:0] pool_data [0:CHANNELS-1];
    logic        pool_last;

    maxpool_2x2 #(
        .DATA_WIDTH(DATA_WIDTH),
        .IMG_WIDTH(IMG_WIDTH),
        .CHANNELS(CHANNELS)
    ) u_maxpool (
        .clk(clk),
        .reset(reset),
        .s_valid(conv_valid),
        .s_ready(conv_ready),
        .s_data(conv_data),
        .s_last(conv_last),
        .m_valid(pool_valid),
        .m_ready(pool_ready),
        .m_data(pool_data),
        .m_last(pool_last)
    );

    // ==========================================
    // Interconnect 4: Dense Layer to Output
    // ==========================================
    logic signed [DATA_WIDTH-1:0] dense_data [0:OUT_CLASSES-1];

    dense_layer_fsm #(
        .DATA_WIDTH(DATA_WIDTH),
        .FRAC_BITS(FRAC_BITS),
        .IN_CHANNELS(CHANNELS),
        .OUT_CLASSES(OUT_CLASSES),
        .IN_FEATURES(IN_FEATURES)
    ) u_dense_layer (
        .clk(clk),
        .reset(reset),
        .s_valid(pool_valid),
        .s_ready(pool_ready),
        .s_data(pool_data),
        .s_last(pool_last),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(dense_data),
        .m_last(m_last)
    );

    // Breakout the dense logits to the output ports
    assign m_data_normal    = dense_data[0];
    assign m_data_unbalance = dense_data[1];
    assign m_data_misalign  = dense_data[2];
    assign m_data_bearing   = dense_data[3];

endmodule