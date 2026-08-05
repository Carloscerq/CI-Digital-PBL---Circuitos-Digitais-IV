`timescale 1ns / 1ps

module dense_layer_fsm (
    input  logic               clk,
    input  logic               rst,
    
    // AXI4-Stream Slave Interface (from maxpool)
    input  logic               s_valid,
    output logic               s_ready,
    input  logic signed [23:0] s_data [0:7],
    input  logic               s_last,
    
    // AXI4-Stream Master Interface (to ArgMax / Output)
    output logic               m_valid,
    input  logic               m_ready,
    output logic signed [23:0] m_data [0:3],
    output logic               m_last
);

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_MAC,
        ST_ADD_BIAS,
        ST_WAIT,
        ST_OUTPUT
    } state_t;

    state_t state, next_state;
    logic [2:0] ch, next_ch;
    logic [1:0] wait_cnt, next_wait_cnt;
    
    logic [11:0] rom_addr;
    logic increment_addr;
    logic reset_addr;

    logic signed [23:0] captured_data [0:7];

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
            for (int i = 0; i < 8; i++) begin
                captured_data[i] <= s_data[i];
            end
        end
    end

    // BRAM/ROM arrays for the 4 outputs (2048 weights each)
    (* ramstyle = "M10K" *) logic signed [23:0] rom0_array [0:2047];
    (* ramstyle = "M10K" *) logic signed [23:0] rom1_array [0:2047];
    (* ramstyle = "M10K" *) logic signed [23:0] rom2_array [0:2047];
    (* ramstyle = "M10K" *) logic signed [23:0] rom3_array [0:2047];

    logic signed [23:0] biases [0:3];
    
    logic signed [23:0] rom0_data;
    logic signed [23:0] rom1_data;
    logic signed [23:0] rom2_data;
    logic signed [23:0] rom3_data;

    // RTL placeholder initialization for pre-trained weights
    initial begin
        for (int i = 0; i < 2048; i++) begin
            rom0_array[i] = 24'h00_0100;
            rom1_array[i] = 24'h00_0100;
            rom2_array[i] = 24'h00_0100;
            rom3_array[i] = 24'h00_0100;
        end
        biases[0] = 24'd0;
        biases[1] = 24'd0;
        biases[2] = 24'd0;
        biases[3] = 24'd0;
    end

    // Synchronous read for BRAM inference
    always_ff @(posedge clk) begin
        rom0_data <= rom0_array[rom_addr];
        rom1_data <= rom1_array[rom_addr];
        rom2_data <= rom2_array[rom_addr];
        rom3_data <= rom3_array[rom_addr];
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
                if (ch == 3'd0 && rom_addr == 12'd1) begin
                    mac_clr = 1'b1;
                end
                
                if (ch < 3'd7) begin
                    increment_addr = 1'b1;
                    next_ch = ch + 1'b1;
                end else begin
                    // Finished the 8 channels for this pixel. Check if it's the last pixel of the frame.
                    if (rom_addr == 12'd2048) begin
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

    // MAC Arrays (4 Parallel DSP Blocks)
    logic signed [23:0] mac_a [0:3];
    logic signed [23:0] mac_b [0:3];
    logic signed [23:0] mac_out [0:3];

    // Multiplexing between feature data and biases
    assign mac_a[0] = (state == ST_ADD_BIAS) ? biases[0] : captured_data[ch];
    assign mac_a[1] = (state == ST_ADD_BIAS) ? biases[1] : captured_data[ch];
    assign mac_a[2] = (state == ST_ADD_BIAS) ? biases[2] : captured_data[ch];
    assign mac_a[3] = (state == ST_ADD_BIAS) ? biases[3] : captured_data[ch];

    // Multiply by 1.0 (Q8.16 = 24'h01_0000) when adding bias
    assign mac_b[0] = (state == ST_ADD_BIAS) ? 24'h01_0000 : rom0_data;
    assign mac_b[1] = (state == ST_ADD_BIAS) ? 24'h01_0000 : rom1_data;
    assign mac_b[2] = (state == ST_ADD_BIAS) ? 24'h01_0000 : rom2_data;
    assign mac_b[3] = (state == ST_ADD_BIAS) ? 24'h01_0000 : rom3_data;

    genvar i;
    generate
        for (i = 0; i < 4; i++) begin : gen_mac
            mac_q8_16 mac_inst (
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
