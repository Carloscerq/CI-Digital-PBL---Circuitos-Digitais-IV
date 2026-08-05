`timescale 1ns/1ps

module tb_dense_layer_fsm();

    logic clk;
    logic rst;
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_data [0:7];
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data [0:3];
    logic m_last;

    // Instantiate Dense FSM
    dense_layer_fsm dut (
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
    task automatic feed_dense();
        begin
            s_valid = 1'b0;
            s_last = 1'b0;
            @(negedge clk);
            
            // Feed 256 pixels (representing 16x16 output of maxpool)
            for (int i = 0; i < 256; i++) begin
                s_valid = 1'b1;
                s_last = (i == 255);
                
                for (int ch = 0; ch < 8; ch++) begin
                    s_data[ch] = 24'h01_0000; // 1.0 in Q8.16
                end
                
                do begin
                    @(negedge clk);
                end while (!s_ready);
                
                s_valid = 1'b0;
                s_last = 1'b0;
                
                // Inject realistic latency between pixel arrivals
                if ($urandom_range(0, 3) == 0) begin
                    @(negedge clk);
                end
            end
        end
    endtask

    // Monitor task
    task automatic monitor_dense();
        begin
            forever begin
                @(negedge clk);
                m_ready = ($urandom_range(0, 3) != 0); // ~75% ready
                
                if (m_valid && m_ready) begin
                    // Expected Accumulation:
                    // 2048 operations. Each is 1.0 * (1/256 weights).
                    // 2048 * (1/256) = 8.0 = 24'h08_0000
                    logic signed [23:0] expected_out = 24'h08_0000;
                    
                    for (int out_idx = 0; out_idx < 4; out_idx++) begin
                        if (m_data[out_idx] !== expected_out) begin
                            $error("[FAIL] Dense Logit %0d Mismatch: Exp %h, Got %h", out_idx, expected_out, m_data[out_idx]);
                            err_count++;
                        end
                    end
                    
                    if (!m_last) begin
                        $error("[FAIL] m_last was not asserted alongside the dense output!");
                        err_count++;
                    end
                    
                    if (err_count == 0) $display("[PASS] Dense Layer properly computed 2048 on-the-fly MAC operations. Outputs perfectly matched 8.0.");
                    break;
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
            feed_dense();
            monitor_dense();
        join
        
        if (err_count == 0) $display("=== ALL DENSE LAYER TESTS PASSED ===");
        $finish;
    end

endmodule
