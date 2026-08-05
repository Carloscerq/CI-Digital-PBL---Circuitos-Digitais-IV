`timescale 1ns/1ps

module tb_line_buffer_3x3();
    
    logic clk;
    logic rst;
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_data;
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_window [0:2][0:2];
    logic m_last;

    line_buffer_3x3 dut (
        .clk(clk),
        .rst(rst),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_data(s_data),
        .s_last(s_last),
        .m_valid(m_valid),
        .m_ready(m_ready),
        .m_window(m_window),
        .m_last(m_last)
    );

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int err_count = 0;
    int valid_out_count = 0;

    // Driver task
    task automatic feed_image();
        begin
            int r, c;
            s_valid = 1'b0;
            s_last = 1'b0;
            s_data = 24'd0;
            
            @(negedge clk);
            
            // Feed a 32x32 image with sequential integer values
            for (r = 0; r < 32; r++) begin
                for (c = 0; c < 32; c++) begin
                    s_valid = 1'b1;
                    s_data = (r * 32 + c + 1);
                    s_last = (r == 31 && c == 31);
                    
                    // Wait until the line buffer actually consumes the data
                    do begin
                        @(negedge clk);
                    end while (!s_ready);
                end
            end
            s_valid = 1'b0;
            s_last = 1'b0;
        end
    endtask

    // Monitor task
    task automatic monitor_output();
        logic signed [23:0] expected_win [0:2][0:2];
        begin
            m_ready = 1'b1;
            valid_out_count = 0;
            
            forever begin
                @(negedge clk);
                // Randomly toggle m_ready to heavily stress the backpressure/stall logic
                m_ready = ($urandom_range(0, 3) != 0); // ~75% ready probability
                
                if (m_valid && m_ready) begin
                    valid_out_count++;
                    
                    // Rigorously check the very first valid window mathematically
                    if (valid_out_count == 1) begin
                        // Expected layout for a 3x3 window centered at pixel (0,0) with Padding=1
                        expected_win[0][0] = 0; expected_win[0][1] = 0; expected_win[0][2] = 0;
                        expected_win[1][0] = 0; expected_win[1][1] = 1; expected_win[1][2] = 2;
                        expected_win[2][0] = 0; expected_win[2][1] = 33; expected_win[2][2] = 34;
                        
                        for (int i=0; i<3; i++) begin
                            for (int j=0; j<3; j++) begin
                                if (m_window[i][j] !== expected_win[i][j]) begin
                                    $error("[FAIL] First Window Mismatch at [%0d][%0d]: Exp %0d, Got %0d", i, j, expected_win[i][j], m_window[i][j]);
                                    err_count++;
                                end
                            end
                        end
                        if (err_count == 0) $display("[PASS] First Valid Window fully matches expected 3x3 padded layout.");
                        else $stop;
                    end
                    
                    if (m_last) begin
                        if (valid_out_count == 1024) begin
                            $display("[PASS] Received exactly 1024 valid windows with m_last asserted correctly.");
                        end else begin
                            $error("[FAIL] m_last asserted at window %0d (Expected 1024)", valid_out_count);
                            err_count++;
                        end
                        break; // End monitor loop
                    end
                end
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        
        #25 rst = 1'b0;
        
        fork
            feed_image();
            monitor_output();
        join
        
        if (err_count == 0) $display("=== ALL LINE BUFFER TESTS PASSED ===");
        $finish;
    end

endmodule
