`timescale 1ns / 1ps

module conv2d_fsm #(
    parameter int DATA_WIDTH = 24,
    parameter int FRAC_BITS = 16,
    parameter int CHANNELS = 8
)(
    input  logic               clk,
    input  logic               rst,
    
    // AXI4-Stream Slave Interface (from line_buffer)
    input  logic               s_valid,
    output logic               s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_window [0:2][0:2],
    input  logic               s_last,
    
    // AXI4-Stream Master Interface (to maxpool)
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data [0:CHANNELS-1],
    output logic               m_last
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_FEED,
        ST_WAIT,
        ST_OUTPUT
    } state_t;
    
    state_t state, next_state;
    logic [3:0] cnt, next_cnt;
    
    // Captured 3x3 window flattened
    logic signed [DATA_WIDTH-1:0] captured_window [0:8];
    logic               captured_last;
    
    // We only capture when accepting a new transaction from the line buffer
    logic capture;
    assign capture = s_valid && s_ready;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ST_IDLE;
            cnt   <= '0;
        end else begin
            state <= next_state;
            cnt   <= next_cnt;
        end
    end
    
    always_ff @(posedge clk) begin
        if (capture) begin
            captured_window[0] <= s_window[0][0];
            captured_window[1] <= s_window[0][1];
            captured_window[2] <= s_window[0][2];
            captured_window[3] <= s_window[1][0];
            captured_window[4] <= s_window[1][1];
            captured_window[5] <= s_window[1][2];
            captured_window[6] <= s_window[2][0];
            captured_window[7] <= s_window[2][1];
            captured_window[8] <= s_window[2][2];
            captured_last      <= s_last;
        end
    end

    // ============================================================================
    // Weights and Biases (Flattened for $readmemh)
    // ============================================================================
    // 8 Channels * 9 pixels = 72 total kernel weights
    logic signed [DATA_WIDTH-1:0] weights_flat [0:(CHANNELS * 9)-1];
    logic signed [DATA_WIDTH-1:0] biases [0:CHANNELS-1];

    initial begin
        // Load the 72 kernel weights
        $readmemh("mem/cnn/conv2d_weights.mem", weights_flat);
        
        // Load the 8 bias values
        $readmemh("mem/cnn/conv2d_biases.mem", biases);
        
        $display("[INIT] Conv2D ROM and Biases successfully loaded from files.");
    end

    // FSM Combinational Logic
    logic mac_en;
    logic mac_clr;
    
    always_comb begin
        next_state = state;
        next_cnt   = cnt;
        s_ready    = 1'b0;
        m_valid    = 1'b0;
        mac_en     = 1'b0;
        mac_clr    = 1'b0;
        
        case (state)
            ST_IDLE: begin
                s_ready = m_ready; // Can accept if downstream won't block us later
                if (s_valid && s_ready) begin
                    next_state = ST_FEED;
                    next_cnt   = '0;
                end
            end
            
            ST_FEED: begin
                mac_en = 1'b1;
                if (cnt == 4'd0) begin
                    mac_clr = 1'b1;
                end
                
                // cnt goes from 0 to 9. 
                // 0-8 feeds the 9 window pixels. 
                // 9 feeds the bias.
                if (cnt == 4'd9) begin
                    next_state = ST_WAIT;
                    next_cnt   = '0;
                end else begin
                    next_cnt = cnt + 1'b1;
                end
            end
            
            ST_WAIT: begin
                mac_en = 1'b1;
                // Wait for the MAC 3-stage pipeline to drain
                // mult_reg computes in ST_WAIT 0
                // acc_reg computes in ST_WAIT 1
                if (cnt == 4'd1) begin
                    next_state = ST_OUTPUT;
                end else begin
                    next_cnt = cnt + 1'b1;
                end
            end
            
            ST_OUTPUT: begin
                m_valid = 1'b1;
                // Halt MAC to keep its output stable
                mac_en = 1'b0;
                
                if (m_ready) begin
                    // We can overlap capturing next data with outputting current data!
                    s_ready = 1'b1;
                    if (s_valid) begin
                        next_state = ST_FEED;
                        next_cnt   = '0;
                    end else begin
                        next_state = ST_IDLE;
                    end
                end
            end
        endcase
    end

    // MAC Array Instantiation
    logic signed [DATA_WIDTH-1:0] mac_a [0:CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] mac_b [0:CHANNELS-1];
    logic signed [DATA_WIDTH-1:0] mac_out [0:CHANNELS-1];

    genvar i;
    generate
        for (i = 0; i < CHANNELS; i++) begin : gen_mac
            // Multiplexer to feed either the window pixel or the bias
            assign mac_a[i] = (cnt < 9) ? captured_window[cnt] : biases[i];
            
            // Safe Flat Addressing for Kernel Weights
            logic [6:0] weight_idx;

            // Calculate 1D index: (channel * 9) + valid_pixel_counter
            assign weight_idx = (i * 9) + ((cnt < 9) ? cnt : 4'd0);
            
            // To add bias, multiply it by 1.0 (Parameterized by FRAC_BITS)
            assign mac_b[i] = (cnt < 9) ? weights_flat[weight_idx] : (DATA_WIDTH'(1) << FRAC_BITS);

            mac_q8_16 #(
                .DATA_WIDTH(DATA_WIDTH),
                .FRAC_BITS(FRAC_BITS)
            ) mac_inst (
                .clk(clk),
                .rst(rst),
                .en(mac_en),
                .clr(mac_clr),
                .a(mac_a[i]),
                .b(mac_b[i]),
                .out(mac_out[i])
            );
            
            // Combinational ReLU at the MAC output
            logic signed [DATA_WIDTH-1:0] relu_out;
            assign relu_out = (mac_out[i][DATA_WIDTH-1] == 1'b1) ? '0 : mac_out[i];
            
            assign m_data[i] = relu_out;
        end
    endgenerate

    assign m_last = captured_last;

endmodule
