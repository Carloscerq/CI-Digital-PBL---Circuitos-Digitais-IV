`timescale 1ns / 1ps

module tb_spectrogram_generator();

    logic clk;
    logic reset;
    
    logic s_valid;
    logic s_ready;
    logic signed [23:0] s_data;
    logic s_last;
    
    logic m_valid;
    logic m_ready;
    logic signed [23:0] m_data;
    logic m_last;

    spectrogram_generator #(
        .DATA_WIDTH(24),
        .BINS_PER_FRAME(32),
        .FRAMES_PER_SPECTROGRAM(32)
    ) dut (.*);

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    int err_count = 0;

    // =========================================================================
    // Write Task (Emulating FFT bursts)
    // =========================================================================
    task automatic feed_fft_frames(input int num_spectrograms);
        begin
            s_valid = 1'b0;
            s_last = 1'b0;
            @(posedge clk);
            
            for (int s = 0; s < num_spectrograms; s++) begin
                for (int f = 0; f < 32; f++) begin // 32 frames
                    for (int b = 0; b < 32; b++) begin // 32 bins per frame
                        s_valid = 1'b1;
                        // Data pattern: spectrogram_idx * 10000 + frame * 100 + bin
                        s_data = (s * 10000) + (f * 100) + b;
                        s_last = (f == 31 && b == 31);
                        
                        @(posedge clk);
                        while (!s_ready) @(posedge clk);
                        
                        s_valid = 1'b0;
                        s_last = 1'b0;
                        
                        // Emulate FFT delay (bursty writes) to stress ping-pong
                        if ($urandom_range(0, 3) == 0) begin
                            repeat($urandom_range(1, 3)) @(posedge clk);
                        end
                    end
                end
            end
        end
    endtask

    // =========================================================================
    // Read Task (Emulating CNN continuous stream)
    // =========================================================================
    task automatic monitor_cnn_frames(input int num_spectrograms);
        begin
            int spec_count = 0;
            int f = 0;
            int b = 0;
            
            forever begin
                @(negedge clk);
                m_ready = ($urandom_range(0, 2) != 0); // 66% ready to simulate CNN backpressure
                
                if (m_valid && m_ready) begin
                    logic signed [23:0] expected_data;
                    expected_data = (spec_count * 10000) + (f * 100) + b;
                    
                    if (m_data !== expected_data) begin
                        $error("[FAIL] Data Mismatch at Spec %0d, Frame %0d, Bin %0d: Exp %0d, Got %0d", 
                               spec_count, f, b, expected_data, m_data);
                        err_count++;
                    end
                    
                    if (f == 31 && b == 31) begin
                        if (!m_last) begin
                            $error("[FAIL] m_last not asserted at end of Spectrogram %0d", spec_count);
                            err_count++;
                        end
                        $display("[PASS] Spectrogram %0d successfully streamed via Ping-Pong Double Buffering.", spec_count);
                        spec_count++;
                        f = 0;
                        b = 0;
                        
                        if (spec_count == num_spectrograms) break;
                    end else begin
                        if (m_last) begin
                            $error("[FAIL] m_last asserted prematurely at Spec %0d, Frame %0d, Bin %0d", 
                                   spec_count, f, b);
                            err_count++;
                        end
                        b++;
                        if (b == 32) begin
                            b = 0;
                            f++;
                        end
                    end
                end
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        s_valid = 1'b0;
        m_ready = 1'b0;
        
        #22 reset = 1'b0;
        
        $display("Starting Ping-Pong Double Buffering Test...");
        
        fork
            // Feed 3 complete spectrograms to heavily exercise the swap logic
            feed_fft_frames(3);
            monitor_cnn_frames(3);
        join
        
        if (err_count == 0) $display("=== ALL SPECTROGRAM TESTS PASSED ===");
        $finish;
    end

endmodule
