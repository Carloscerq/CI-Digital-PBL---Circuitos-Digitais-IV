`timescale 1ns/1ps

module tb_cnn_top();

    logic clk;
    logic reset;
    
    // Interface signals matching cnn_top
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_data [0:3];
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data_normal;
    logic signed [23:0] m_data_unbalance;
    logic signed [23:0] m_data_misalign;
    logic signed [23:0] m_data_bearing;
    logic m_last;

    // Testbench Memory for Golden Model Input
    // 32x32 = 1024 pixels. 4 channels per pixel = 4096 values.
    logic [23:0] tb_image_data [0:4095];

    initial begin
        $readmemh("../Scripts/cnn/cnn_tb_input.mem", tb_image_data);
        $display("[INIT] Golden Model Spectrogram (4-channel) loaded into TB memory.");
    end

    // Instantiate the CNN Top Module
    cnn_top #(
        .DATA_WIDTH(24),
        .FRAC_BITS(16),
        .IMG_WIDTH(32),
        .IMG_HEIGHT(32),
        .IN_CHANNELS(4),
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
            s_valid = 1'b0;
            s_last  = 1'b0;
            for(int ch=0;ch<4;ch++) s_data[ch] = '0;
            @(negedge clk);
            
            // Stream the image pixel by pixel (all 4 channels concurrently)
            for (int i = 0; i < 1024; i++) begin
                s_valid = 1'b1;
                
                // Read the interleaved channel data directly from memory
                s_data[0] = tb_image_data[(i * 4) + 0];
                s_data[1] = tb_image_data[(i * 4) + 1];
                s_data[2] = tb_image_data[(i * 4) + 2];
                s_data[3] = tb_image_data[(i * 4) + 3];
                
                // Assert LAST signal on the very last pixel
                s_last  = (i == 1023);
                
                @(posedge clk);
                // Wait if the CNN asserts backpressure
                while (!s_ready) @(posedge clk);
            end
            
            s_valid = 1'b0;
            s_last  = 1'b0;
        end
    endtask

    // Monitor task
    task automatic monitor_top();
        begin
            forever begin
                @(negedge clk);
                m_ready = ($urandom_range(0, 2) != 0); // test pipeline stalls
                
                if (m_valid && m_ready) begin
                    $display("---------------------------------------------------------");
                    $display("[OUTPUT CAPTURED] Neural Network Final Logits:");
                    $display("  Normal    : %h | %d", m_data_normal, m_data_normal);
                    $display("  Unbalance : %h | %d", m_data_unbalance, m_data_unbalance);
                    $display("  Misalign  : %h | %d", m_data_misalign, m_data_misalign);
                    $display("  Bearing   : %h | %d", m_data_bearing, m_data_bearing);
                    $display("---------------------------------------------------------");
                    
                    if (!m_last) begin
                        $error("[FAIL] m_last not asserted at end of frame!");
                        err_count++;
                    end
                    
                    break;
                end
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        
        #22 reset = 1'b0;
        
        fork
            feed_top();
            monitor_top();
        join
        
        if (err_count == 0) $display("=== ALL TOP LEVEL CNN TESTS PASSED ===");
        $finish;
    end

endmodule
