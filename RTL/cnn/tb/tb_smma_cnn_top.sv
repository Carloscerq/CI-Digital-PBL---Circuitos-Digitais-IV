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

    // Instantiate Top Module
    smma_cnn_top dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int err_count = 0;

    // Driver task
    task automatic feed_top();
        begin
            s_axis_valid = 1'b0;
            s_axis_last = 1'b0;
            @(negedge clk);
            
            // Stream a complete 32x32 image (1024 pixels) of constant 1.0
            for (int r = 0; r < 32; r++) begin
                for (int c = 0; c < 32; c++) begin
                    s_axis_valid = 1'b1;
                    s_axis_data = 24'h01_0000; // 1.0
                    s_axis_last = (r == 31 && c == 31);
                    
                    @(posedge clk);
                    while (!s_axis_ready) @(posedge clk);
                end
            end
            s_axis_valid = 1'b0;
            s_axis_last = 1'b0;
        end
    endtask

    // Monitor task
    task automatic monitor_top();
        begin
            forever begin
                @(negedge clk);
                m_axis_ready = ($urandom_range(0, 2) != 0); // ~66% ready to test heavy pipeline stalls
                
                if (m_axis_valid && m_axis_ready) begin
                    // Mathematical Propagation Trace:
                    // 1. Line buffer emits overlapping 3x3 grids.
                    // 2. Conv2D multiplies 9 elements of 1.0 by 1/256. Sum = 9/256.
                    // 3. MaxPool checks 2x2 grids. Since the image is solid, all regions have 
                    //    a window fully inside the frame (val = 9/256). Max = 9/256 (24'h00_0900).
                    // 4. Dense receives 256 MaxPool outputs (each with 8 channels = 2048 ops).
                    // 5. Hardware MAC accumulation: 2048 * (2304 * 256).
                    //    In decimal accumulation register: 2048 * 589824 = 1207959552 = 0x48000000.
                    // 6. Q8.16 Hardware Truncation (Right shift 16): 0x48000000 >> 16 = 0x004800.
                    // Thus, the expected final output is precisely 24'h00_4800.
                    
                    logic signed [23:0] expected_out = 24'h00_4800;
                    
                    if (m_axis_data_normal !== expected_out) begin
                        $error("[FAIL] Normal Mismatch: Exp %h, Got %h", expected_out, m_axis_data_normal); err_count++;
                    end
                    if (m_axis_data_unbalance !== expected_out) begin
                        $error("[FAIL] Unbalance Mismatch: Exp %h, Got %h", expected_out, m_axis_data_unbalance); err_count++;
                    end
                    if (m_axis_data_misalign !== expected_out) begin
                        $error("[FAIL] Misalign Mismatch: Exp %h, Got %h", expected_out, m_axis_data_misalign); err_count++;
                    end
                    if (m_axis_data_bearing !== expected_out) begin
                        $error("[FAIL] Bearing Mismatch: Exp %h, Got %h", expected_out, m_axis_data_bearing); err_count++;
                    end
                    
                    if (!m_axis_last) begin
                        $error("[FAIL] m_axis_last not asserted at end of frame!"); err_count++;
                    end
                    
                    if (err_count == 0) $display("[PASS] FULL DATAPATH VERIFIED! Outputs match mathematical propagation precisely (24'h00_4800).");
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
