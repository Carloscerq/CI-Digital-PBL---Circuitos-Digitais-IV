`timescale 1ns/1ps

module tb_conv2d_fsm();

    logic clk;
    logic rst;
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_window [0:3][0:2][0:2];
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data [0:7];
    logic m_last;

    // Instantiate Conv2D FSM
    conv2d_fsm #(
        .DATA_WIDTH(24),
        .FRAC_BITS(16),
        .CHANNELS(8),
        .IN_CHANNELS(4)
    ) dut (
        .clk(clk),
        .rst(rst),
        .s_valid(s_valid),
        .s_ready(s_ready),
        .s_window(s_window),
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

    // Driver Task
    task automatic feed_windows(input int count, input bit positive);
        begin
            for (int i = 0; i < count; i++) begin
                s_valid = 1'b1;
                s_last = (i == count - 1);
                
                for (int ch = 0; ch < 4; ch++) begin
                    for (int r = 0; r < 3; r++) begin
                        for (int c = 0; c < 3; c++) begin
                            s_window[ch][r][c] = positive ? 24'h01_0000 : 24'hFF_0000;
                        end
                    end
                end
                
                @(posedge clk);
                while (!s_ready) @(posedge clk);
                
                s_valid = 1'b0;
                s_last = 1'b0;
                
                if ($urandom_range(0, 2) == 0) begin
                    repeat(2) @(posedge clk);
                end
            end
        end
    endtask

    // Monitor Task
    task automatic monitor_outputs(input int count);
        begin
            int observed = 0;
            while (observed < count) begin
                @(negedge clk);
                
                m_ready = ($urandom_range(0, 3) != 0);
                
                if (m_valid && m_ready) begin
                    observed++;
                    
                    $display("Received output %0d: [%h, %h, %h, %h, %h, %h, %h, %h]", 
                        observed, m_data[0], m_data[1], m_data[2], m_data[3], m_data[4], m_data[5], m_data[6], m_data[7]);
                    
                    if (observed == count) begin
                        if (!m_last) begin
                            $error("[FAIL] m_last not asserted on final window!");
                            err_count++;
                        end
                    end else begin
                        if (m_last) begin
                            $error("[FAIL] m_last asserted prematurely at window %0d", observed);
                            err_count++;
                        end
                    end
                end
            end
            if (err_count == 0) $display("[PASS] Received %0d valid outputs.", count);
        end
    endtask

    initial begin
        rst = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        s_last = 1'b0;
        
        #22 rst = 1'b0;
        
        $display("--- Starting Liveness Test ---");
        fork
            feed_windows(10, 1'b1);
            monitor_outputs(10);
        join
        
        if (err_count == 0) $display("=== ALL CONV2D TESTS PASSED ===");
        $finish;
    end

endmodule
