`timescale 1ns/1ps

module tb_maxpool_2x2();

    logic clk;
    logic rst;
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_data [0:7];
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data [0:7];
    logic m_last;

    // Instantiate MaxPool 2x2
    maxpool_2x2 #(
        .DATA_WIDTH(24),
        .IMG_WIDTH(32),
        .CHANNELS(8)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .s_last(s_last),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_data(m_data),
        .m_last(m_last)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int err_count = 0;

    // Driver task
    task automatic feed_pool();
        begin
            int r, c;
            s_valid = 1'b0;
            s_last  = 1'b0;
            for (int ch = 0; ch < 8; ch++) s_data[ch] = '0;
            
            // Feed a 32x32 stream representing the feature map
            for (r = 0; r < 32; r++) begin
                for (c = 0; c < 32; c++) begin
                    
                    // 1. Wait for the FALLING edge to inject data using '='
                    // This gives the signals half a clock cycle to stabilize before the DUT reads them.
                    @(negedge clk);
                    s_valid = 1'b1;
                    s_last  = (r == 31 && c == 31);
                    
                    // Assign identical deterministic values to all 8 channels
                    for (int ch = 0; ch < 8; ch++) begin
                        s_data[ch] = (r * 32 + c + 1);
                    end
                    
                    // 2. Wait for the RISING edge to check if DUT consumed the data
                    @(posedge clk);
                    while (!s_ready) begin
                        // If the DUT applies backpressure, wait for the next rising edge
                        // The AXI signals remain perfectly stable during this stall.
                        @(posedge clk);
                    end
                end
            end
            
            // Clean up signals safely on the next falling edge
            @(negedge clk);
            s_valid = 1'b0;
            s_last  = 1'b0;
        end
    endtask

    // Monitor task
    task automatic monitor_pool();
        begin
            int r_out = 0;
            int c_out = 0;
            int valid_count = 0;
            
            forever begin
                @(negedge clk);
                // Heavy randomized backpressure
                m_ready = ($urandom_range(0, 3) != 0);
                
                if (m_valid && m_ready) begin
                    logic signed [23:0] expected_max;
                    
                    // Because stride=2, the 2x2 window top-left is at (r_out*2, c_out*2).
                    // The mathematically highest value will always be at the bottom-right of the 2x2 grid:
                    // (r+1)*32 + c + 2
                    expected_max = ((r_out * 2 + 1) * 32 + (c_out * 2) + 2);
                    
                    valid_count++;
                    
                    for (int ch = 0; ch < 8; ch++) begin
                        if (m_data[ch] !== expected_max) begin
                            $error("[FAIL] MaxPool Mismatch at out(%0d,%0d) ch %0d: Exp %0d, Got %0d", r_out, c_out, ch, expected_max, m_data[ch]);
                            err_count++;
                        end
                    end
                    
                    if (m_last) begin
                        if (valid_count !== 256) begin
                            $error("[FAIL] Expected 256 outputs, got %0d", valid_count);
                            err_count++;
                        end else begin
                            $display("[PASS] Received exactly 256 mathematically verified maxima.");
                        end
                        break;
                    end
                    
                    // Advance expected coordinates
                    c_out++;
                    if (c_out == 16) begin
                        c_out = 0;
                        r_out++;
                    end
                end
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        
        #22 rst = 1'b0;
        
        fork
            feed_pool();
            monitor_pool();
        join
        
        if (err_count == 0) $display("=== ALL MAXPOOL TESTS PASSED ===");
        $finish;
    end

endmodule
