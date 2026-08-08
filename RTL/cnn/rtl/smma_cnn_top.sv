`timescale 1ns/1ps

module tb_smma_cnn_top();

    logic clk;
    logic rst;
    logic s_axis_valid;
    logic s_axis_ready;
    logic signed [23:0] s_axis_data;
    logic s_axis_last;
    
    logic m_axis_valid;
    logic m_axis_ready;
    logic signed [23:0] m_axis_data_normal;
    logic signed [23:0] m_axis_data_unbalance;
    logic signed [23:0] m_axis_data_misalign;
    logic signed [23:0] m_axis_data_bearing;
    logic m_axis_last;

    // ============================================================================
    // Testbench Memory for Golden Model Input
    // ============================================================================
    // The spectrogram is 32x32 = 1024 pixels
    logic [23:0] tb_image_data [0:1023];

    initial begin
        // Load the exported Python spectrogram before the simulation starts
        $readmemh("cnn_tb_input.mem", tb_image_data);
        $display("[INIT] Golden Model Spectrogram loaded into TB memory.");
    end

    // Instantiate the CNN Top Module
    smma_cnn_top #(
        .DATA_WIDTH(24),
        .FRAC_BITS(16),
        .IMG_WIDTH(32),
        .IMG_HEIGHT(32),
        .CHANNELS(8),
        .OUT_CLASSES(4),
        .IN_FEATURES(2048)
    ) dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int err_count = 0;

    // Driver task
    task automatic feed_top();
        begin
            s_axis_valid = 1'b0;
            s_axis_last  = 1'b0;
            s_axis_data  = '0;
            @(negedge clk);
            
            // Stream the image pixel by pixel from the loaded memory
            for (int i = 0; i < 1024; i++) begin
                s_axis_valid = 1'b1;
                s_axis_data  = tb_image_data[i];
                
                // Assert LAST signal on the very last pixel
                s_axis_last  = (i == 1023);
                
                @(posedge clk);
                // Wait if the CNN asserts backpressure (stalls)
                while (!s_axis_ready) @(posedge clk);
            end
            
            // End of transmission
            s_axis_valid = 1'b0;
            s_axis_last  = 1'b0;
        end
    endtask

    // Monitor task
    task automatic monitor_top();
        begin
            // ============================================================================
            // GOLDEN MODEL EXPECTED OUTPUTS
            // ============================================================================
            // IMPORTANT: Replace these hex values with the exact 'raw_q8_logits' 
            // printed by your Python script in the terminal!
            logic signed [23:0] exp_normal    = 24'h00_0000; // <-- INSERT HERE
            logic signed [23:0] exp_unbalance = 24'h00_0000; // <-- INSERT HERE
            logic signed [23:0] exp_misalign  = 24'h00_0000; // <-- INSERT HERE
            logic signed [23:0] exp_bearing   = 24'h00_0000; // <-- INSERT HERE

            forever begin
                @(negedge clk);
                m_axis_ready = ($urandom_range(0, 2) != 0); // ~66% ready to test heavy pipeline stalls
                
                if (m_axis_valid && m_axis_ready) begin
                    
                    if (m_axis_data_normal !== exp_normal) begin
                        $error("[FAIL] Normal Mismatch: Exp %h, Got %h", exp_normal, m_axis_data_normal); err_count++;
                    end
                    if (m_axis_data_unbalance !== exp_unbalance) begin
                        $error("[FAIL] Unbalance Mismatch: Exp %h, Got %h", exp_unbalance, m_axis_data_unbalance); err_count++;
                    end
                    if (m_axis_data_misalign !== exp_misalign) begin
                        $error("[FAIL] Misalign Mismatch: Exp %h, Got %h", exp_misalign, m_axis_data_misalign); err_count++;
                    end
                    if (m_axis_data_bearing !== exp_bearing) begin
                        $error("[FAIL] Bearing Mismatch: Exp %h, Got %h", exp_bearing, m_axis_data_bearing); err_count++;
                    end
                    
                    if (!m_axis_last) begin
                        $error("[FAIL] m_axis_last not asserted at end of frame!"); err_count++;
                    end
                    
                    if (err_count == 0) $display("[PASS] FULL DATAPATH VERIFIED! Outputs match Golden Model precisely.");
                    break;
                end
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        s_axis_valid = 1'b0;
        m_axis_ready = 1'b0;
        
        #22 rst = 1'b0;
        
        fork
            feed_top();
            monitor_top();
        join
        
        if (err_count == 0) $display("=== ALL TOP LEVEL CNN TESTS PASSED ===");
        $finish;
    end

endmodule