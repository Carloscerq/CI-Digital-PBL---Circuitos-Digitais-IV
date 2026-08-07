`timescale 1ns / 1ps

module dense_layer_fsm #(
    parameter int DATA_WIDTH = 24,
    parameter int FRAC_BITS = 16,
    parameter int IN_CHANNELS = 8,
    parameter int OUT_CLASSES = 4,
    parameter int IN_FEATURES = 2048 // Total flattened features
)(
    input  logic               clk,
    input  logic               rst,
    
    // AXI4-Stream Slave Interface (from maxpool)
    input  logic               s_valid,
    output logic               s_ready,
    input  logic signed [DATA_WIDTH-1:0] s_data [0:IN_CHANNELS-1],
    input  logic               s_last,
    
    // AXI4-Stream Master Interface (to ArgMax / Output)
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [DATA_WIDTH-1:0] m_data [0:OUT_CLASSES-1],
    output logic               m_last
);
	
	 localparam TOTAL_WEIGHTS = OUT_CLASSES * IN_FEATURES;
    localparam ADDR_WIDTH = $clog2(TOTAL_WEIGHTS);
 
    typedef enum logic [2:0] {
        ST_IDLE,
        ST_MAC,
        ST_ADD_BIAS,
        ST_WAIT,
        ST_OUTPUT
    } state_t;

    state_t state, next_state;
    logic [$clog2(IN_CHANNELS)-1:0] ch, next_ch;
    logic [1:0] wait_cnt, next_wait_cnt;
    
    logic [$clog2(IN_FEATURES+1)-1:0] rom_addr;
    logic increment_addr;
    logic reset_addr;

    logic signed [DATA_WIDTH-1:0] captured_data [0:IN_CHANNELS-1];

    // State, channel, wait counter, and ROM address registers
    always_ff @(posedge clk) begin
        if (rst) begin
            state    <= ST_IDLE;
            ch       <= '0;
            wait_cnt <= '0;
            rom_addr <= '0;
        end else begin
            state    <= next_state;
            ch       <= next_ch;
            wait_cnt <= next_wait_cnt;
            
            if (reset_addr) begin
                rom_addr <= '0;
            end else if (increment_addr) begin
                rom_addr <= rom_addr + 1'b1;
            end
        end
    end

    // Capture incoming pixel channels
    always_ff @(posedge clk) begin
        if (state == ST_IDLE && s_valid && s_ready) begin
            for (int i = 0; i < IN_CHANNELS; i++) begin
                captured_data[i] <= s_data[i];
            end
        end
    end

    // ============================================================================
    // BRAM/ROM Arrays (Flattened 1D array for $readmemh compatibility)
    // ============================================================================
    logic signed [DATA_WIDTH-1:0] rom_array [0:(OUT_CLASSES * IN_FEATURES) - 1];
    logic signed [DATA_WIDTH-1:0] biases [0:OUT_CLASSES-1];
    
    logic signed [DATA_WIDTH-1:0] rom_data [0:OUT_CLASSES-1];

    // ============================================================================
    // ROM INITIALIZATION (Synthesizable M10K Inference)
    // ============================================================================
    // Quartus will read the .mem files during Analysis & Synthesis and 
    // permanently burn these values into the FPGA block RAM.
    
    initial begin
        // Load the 8192 weights (4 classes * 2048 features)
        $readmemh("dense_weights.mem", rom_array);
        
        // Load the 4 bias values
        $readmemh("dense_biases.mem", biases);
        
        $display("[INIT] Dense Layer ROM and Biases successfully loaded from files.");
    end

    // ============================================================================
    // Synchronous read for BRAM inference with flat addressing
    // ============================================================================
    always_ff @(posedge clk) begin
        for (int c = 0; c < OUT_CLASSES; c++) begin
            // Prevent out-of-bounds ghost reads when rom_addr hits exactly IN_FEATURES
            if (rom_addr < IN_FEATURES) begin
                // Explicitly cast the mathematical result to the correct bus width (ADDR_WIDTH)
                rom_data[c] <= rom_array[ ADDR_WIDTH'( (c * IN_FEATURES) + rom_addr ) ];
            end
        end
    end

    // FSM Combinational Logic
    logic mac_en;
    logic mac_clr;

    always_comb begin
        next_state     = state;
        next_ch        = ch;
        next_wait_cnt  = wait_cnt;
        
        s_ready        = 1'b0;
        m_valid        = 1'b0;
        m_last         = 1'b0;
        
        mac_en         = 1'b0;
        mac_clr        = 1'b0;
        
        increment_addr = 1'b0;
        reset_addr     = 1'b0;

        case (state)
            ST_IDLE: begin
                // Ready to accept data if we are looking for a new pixel
                s_ready = 1'b1;
                if (s_valid) begin
                    increment_addr = 1'b1;
                    next_state     = ST_MAC;
                    next_ch        = '0;
                end
            end

            ST_MAC: begin
                mac_en = 1'b1;
                
                // Clear MAC on the very first channel of the very first pixel
                if (ch == '0 && rom_addr == 1) begin
                    mac_clr = 1'b1;
                end
                
                if (ch < IN_CHANNELS - 1) begin
                    increment_addr = 1'b1;
                    next_ch = ch + 1'b1;
                end else begin
                    // Finished the channels for this pixel. Check if it's the last pixel of the frame.
                    if (rom_addr == IN_FEATURES) begin
                        next_state = ST_ADD_BIAS;
                    end else begin
                        next_state = ST_IDLE; // Go wait for the next pixel
                    end
                end
            end

            ST_ADD_BIAS: begin
                mac_en = 1'b1;
                next_state = ST_WAIT;
                next_wait_cnt = '0;
            end

            ST_WAIT: begin
                mac_en = 1'b1; // Keep enabled to allow pipeline to progress
                if (wait_cnt == 2'd1) begin
                    next_state = ST_OUTPUT;
                end else begin
                    next_wait_cnt = wait_cnt + 1'b1;
                end
            end

            ST_OUTPUT: begin
                m_valid = 1'b1;
                m_last  = 1'b1; // The dense layer calculates logits for the entire frame once
                mac_en  = 1'b0; // Halt MAC to preserve stable output
                
                if (m_ready) begin
                    reset_addr = 1'b1;
                    next_state = ST_IDLE;
                end
            end
        endcase
    end

    // MAC Arrays (Parallel DSP Blocks)
    logic signed [DATA_WIDTH-1:0] mac_a [0:OUT_CLASSES-1];
    logic signed [DATA_WIDTH-1:0] mac_b [0:OUT_CLASSES-1];
    logic signed [DATA_WIDTH-1:0] mac_out [0:OUT_CLASSES-1];

    genvar i;
    generate
        for (i = 0; i < OUT_CLASSES; i++) begin : gen_mac
            // Multiplexing between feature data and biases
            assign mac_a[i] = (state == ST_ADD_BIAS) ? biases[i] : captured_data[ch];
            
            // Multiply by 1.0 when adding bias
            assign mac_b[i] = (state == ST_ADD_BIAS) ? (DATA_WIDTH'(1) << FRAC_BITS) : rom_data[i];

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
            
            // Output raw logits for final argmax downstream
            assign m_data[i] = mac_out[i];
        end
    endgenerate

endmodule
