`timescale 1ns/1ps

module tb_mac_q8_16();

    logic clk;
    logic rst;
    logic en;
    logic clr;
    logic signed [23:0] a;
    logic signed [23:0] b;
    logic signed [23:0] out;

    // Instantiate MAC
    mac_q8_16 dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clr(clr),
        .a(a),
        .b(b),
        .out(out)
    );

    // Clock generation (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test Variables
    int err_count = 0;

    task automatic run_mac_test();
        logic signed [23:0] exp;
        begin
            // Test 1: Pos * Pos (1.5 * 2.0 = 3.0)
            @(negedge clk);
            en = 1'b1;
            clr = 1'b1;
            a = 24'h01_8000;
            b = 24'h02_0000;
            
            @(negedge clk);
            clr = 1'b0;
            a = 24'd0; b = 24'd0; // Feed zeros to not accumulate more
            
            @(negedge clk);
            @(negedge clk);
            
            // Output is ready
            exp = 24'h03_0000;
            if (out !== exp) begin
                $error("[FAIL] Pos * Pos: Expected %h, Got %h", exp, out);
                err_count++; $stop;
            end else $display("[PASS] Pos * Pos (1.5 * 2.0 = 3.0)");

            // Test 2: Pos * Neg (2.0 * -0.5 = -1.0)
            @(negedge clk);
            en = 1'b1; clr = 1'b1;
            a = 24'h02_0000; b = 24'hFF_8000;
            @(negedge clk);
            clr = 1'b0; a = 24'd0; b = 24'd0;
            @(negedge clk); @(negedge clk);
            exp = 24'hFF_0000;
            if (out !== exp) begin
                $error("[FAIL] Pos * Neg: Expected %h, Got %h", exp, out);
                err_count++; $stop;
            end else $display("[PASS] Pos * Neg (2.0 * -0.5 = -1.0)");

            // Test 3: Neg * Neg (-1.5 * -2.0 = 3.0)
            @(negedge clk);
            en = 1'b1; clr = 1'b1;
            a = 24'hFE_8000; b = 24'hFE_0000;
            @(negedge clk);
            clr = 1'b0; a = 24'd0; b = 24'd0;
            @(negedge clk); @(negedge clk);
            exp = 24'h03_0000;
            if (out !== exp) begin
                $error("[FAIL] Neg * Neg: Expected %h, Got %h", exp, out);
                err_count++; $stop;
            end else $display("[PASS] Neg * Neg (-1.5 * -2.0 = 3.0)");

            // Test 4: Pipelined Accumulation
            // Cycle 0: 0.5 * 2.0 = 1.0
            // Cycle 1: 1.5 * -1.0 = -1.5
            // Cycle 2: 0.5 * 0.5 = 0.25
            // Final accumulation = 1.0 - 1.5 + 0.25 = -0.25 (24'hFF_C000)
            @(negedge clk);
            en = 1'b1; clr = 1'b1;
            a = 24'h00_8000; b = 24'h02_0000;
            
            @(negedge clk);
            clr = 1'b0;
            a = 24'h01_8000; b = 24'hFF_0000;
            
            @(negedge clk);
            a = 24'h00_8000; b = 24'h00_8000;
            
            @(negedge clk); // Pipeline propagation
            a = 24'd0; b = 24'd0;
            
            @(negedge clk); // Pipeline propagation
            @(negedge clk); // Output ready
            
            exp = 24'hFF_C000;
            if (out !== exp) begin
                $error("[FAIL] Pipelined Accumulation: Expected %h, Got %h", exp, out);
                err_count++; $stop;
            end else $display("[PASS] Pipelined Accumulation (1.0 - 1.5 + 0.25 = -0.25)");
        end
    endtask

    initial begin
        rst = 1'b1;
        en = 1'b0;
        clr = 1'b0;
        a = '0; b = '0;
        
        #20 rst = 1'b0;
        
        run_mac_test();
        
        if (err_count == 0) $display("=== ALL MAC TESTS PASSED ===");
        $finish;
    end

endmodule
