`timescale 1ns/1ps

module tb_conv2d_fsm();

    logic clk;
    logic rst;
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_window [0:2][0:2];
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data [0:7];
    logic m_last;

    // Instantiate Conv2D FSM
    conv2d_fsm dut (
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
    // Feeds identical pixel values to fully evaluate FSM multiplication sequencing
    task automatic feed_windows(input int count, input bit positive);
        begin
            for (int i = 0; i < count; i++) begin
                s_valid = 1'b1;
                s_last = (i == count - 1);
                
                for (int r = 0; r < 3; r++) begin
                    for (int c = 0; c < 3; c++) begin
                        // 1.0 (24'h01_0000) or -1.0 (24'hFF_0000)
                        s_window[r][c] = positive ? 24'h01_0000 : 24'hFF_0000;
                    end
                end
                
                do begin
                    @(negedge clk);
                end while (!s_ready);
                
                s_valid = 1'b0;
                s_last = 1'b0;
                
                // Allow occasional idle bubbles to test stability
                if ($urandom_range(0, 2) == 0) begin
                    repeat(2) @(negedge clk);
                end
            end
        end
    endtask

    // Monitor Task
    task automatic monitor_outputs(input int count, input logic signed [23:0] expected_val);
        begin
            int observed = 0;
            while (observed < count) begin
                @(negedge clk);
                
                // Randomize backpressure to ensure FSM halts safely
                m_ready = ($urandom_range(0, 3) != 0);
                
                if (m_valid && m_ready) begin
                    observed++;
                    for (int f = 0; f < 8; f++) begin
                        if (m_data[f] !== expected_val) begin
                            $error("[FAIL] Filter %0d Mismatch: Exp %h, Got %h", f, expected_val, m_data[f]);
                            err_count++;
                        end
                    end
                    
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
            if (err_count == 0) $display("[PASS] Received %0d outputs exactly matching %h", count, expected_val);
        end
    endtask

    initial begin
        rst = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        s_last = 1'b0;
        
        #25 rst = 1'b0;
        
        // Test 1: Positive Values (ReLU Passes)
        // Internal dummy weights are 0.00390625 (24'h00_0100)
        // 9 * 1.0 * 0.00390625 = 9 * 256 = 2304 = 24'h00_0900
        $display("--- Starting Positive Values Test ---");
        fork
            feed_windows(10, 1'b1);
            monitor_outputs(10, 24'h00_0900);
        join
        
        // Test 2: Negative Values (ReLU Clamps)
        // 9 * -1.0 * 0.00390625 = -2304
        // ReLU should strictly clamp to 0
        $display("--- Starting Negative Values (ReLU) Test ---");
        fork
            feed_windows(5, 1'b0);
            monitor_outputs(5, 24'd0);
        join
        
        if (err_count == 0) $display("=== ALL CONV2D TESTS PASSED ===");
        $finish;
    end

endmodule
