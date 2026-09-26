`timescale 1ns / 1ps

// ============================================================================
// tb_top_system_de0cv -- checks the board wrapper's telemetry path
// ============================================================================
// Scope is deliberately narrow: the wrapper's own additions, which nothing else
// covers. tb_top_system already exercises framing, the checksum, error
// injection and the DSP/inference chain through top_system's logical ports, and
// this does not duplicate any of it.
//
// What it checks:
//   - the telemetry line idles high and reports at all, with no reset press
//   - a report parses as "B=xxxx E=xx S=x F=x A=x\r\n"
//   - B equals the number of bytes actually put on the serial line, so the
//     snooping receiver counts bytes rather than edges
//   - B keeps counting across a second report
//   - M/N and C/K: a verdict strobe is counted once per rising edge (even when
//     held high for several cycles) and its class is reported. The strobes
//     are forced from here rather than earned: a real MLP verdict needs 2048
//     valid frames and a CNN verdict 65536, which is tb_top_system's job.
//
// >>> SPEED_NOTE <<<
// The telemetry period and the power-on stretch are parameters so this can run
// in milliseconds instead of the half-second the board uses. The baud divisor
// stays exact, so only the report cadence changes.
// ============================================================================
module tb_top_system_de0cv #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 1_562_500     // fast divisor; see SPEED_NOTE
);

    localparam int BIT_CYCLES   = CLK_FREQ_HZ / BAUD_RATE;
    localparam int TELEM_PERIOD = 40_000;     // ~0.8 ms, vs CLK_FREQ_HZ/2 on the board
    localparam int POR_CYCLES   = 64;

    logic clk = 1'b0;
    always #10ns clk = ~clk;

    logic [0:0] key = 1'b1;                   // released (active low)
    logic [0:0] sw  = 1'b0;                   // reset not held
    logic [4:4] gpio1;                        // sensor stream in
    logic [4:4] gpio0;                        // telemetry out
    logic [9:0] ledr;
    logic [6:0] hex0, hex1, hex2, hex3;

    assign gpio1[4] = rx_drive;
    logic rx_drive = 1'b1;                    // idle high

    top_system_de0cv #(
        .CLK_FREQ_HZ         (CLK_FREQ_HZ),
        .BAUD_RATE           (BAUD_RATE),
        .POR_CYCLES          (POR_CYCLES),
        .TELEM_PERIOD_CYCLES (TELEM_PERIOD)
    ) dut (
        .CLOCK_50 (clk),
        .KEY      (key),
        .SW       (sw),
        .GPIO_1   (gpio1),
        .GPIO_0   (gpio0),
        .LEDR     (ledr),
        .HEX0     (hex0),
        .HEX1     (hex1),
        .HEX2     (hex2),
        .HEX3     (hex3)
    );

    // ------------------------------------------------------------------ score
    int errors = 0, checks = 0;

    function automatic void check(input bit cond, input string what);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] FAIL: %s", $time, what);
        end
    endfunction

    // ------------------------------------------------------- host transmitter
    int bytes_sent = 0;

    task automatic host_send(input logic [7:0] v);
        rx_drive = 1'b0;  repeat (BIT_CYCLES) @(posedge clk);
        for (int i = 0; i < 8; i++) begin
            rx_drive = v[i]; repeat (BIT_CYCLES) @(posedge clk);
        end
        rx_drive = 1'b1;  repeat (BIT_CYCLES) @(posedge clk);
        bytes_sent++;
    endtask

    // ---------------------------------------------------- telemetry decoder
    // Collects whole CR/LF-terminated lines off the telemetry pin.
    string lines [$];

    initial begin : telem_monitor
        logic [7:0] b;
        string cur = "";
        forever begin
            @(negedge gpio0[4]);
            repeat (BIT_CYCLES/2) @(posedge clk);
            if (gpio0[4] !== 1'b0) continue;             // not a start bit
            for (int i = 0; i < 8; i++) begin
                repeat (BIT_CYCLES) @(posedge clk);
                b[i] = gpio0[4];
            end
            repeat (BIT_CYCLES) @(posedge clk);
            if (gpio0[4] !== 1'b1)
                $display("[%0t] FAIL: telemetry stop bit low after %02h", $time, b);
            if (b == 8'h0A) begin
                lines.push_back(cur);
                cur = "";
            end else if (b != 8'h0D) begin
                cur = {cur, string'(b)};
            end
        end
    end

    task automatic await_line(output string got);
        int guard = 0;
        int n = lines.size();
        while (lines.size() == n && guard < 200 * TELEM_PERIOD) begin
            @(posedge clk);
            guard++;
        end
        got = (lines.size() > n) ? lines[lines.size()-1] : "";
    endtask

    // Pulls the hex value of "<key>=" out of a telemetry line.
    function automatic int field(input string s, input string key, input int width);
        int p = -1;
        int v = 0;
        for (int i = 0; i + key.len() <= s.len(); i++)
            if (s.substr(i, i + key.len() - 1) == key) p = i + key.len();
        if (p < 0 || p + width > s.len()) return -1;
        for (int i = 0; i < width; i++) begin
            byte c = s[p + i];
            int d;
            if      (c >= "0" && c <= "9") d = c - "0";
            else if (c >= "A" && c <= "F") d = c - "A" + 10;
            else return -1;
            v = v * 16 + d;
        end
        return v;
    endfunction

    // ------------------------------------------------------------------- main
    initial begin
        string ln;
        int b_field;

        $display("=== tb_top_system_de0cv: %0d baud, %0d clk/bit, telem every %0d clk ===",
                 BAUD_RATE, BIT_CYCLES, TELEM_PERIOD);

        repeat (4 * POR_CYCLES) @(posedge clk);
        check(gpio0[4] === 1'b1, "telemetry line idles high after power-on reset");

        // First report, before any traffic: B must be zero.
        await_line(ln);
        $display("  report 1: \"%s\"", ln);
        check(ln != "", "a telemetry report arrives with no host traffic");
        check(field(ln, "B=", 4) == 0, $sformatf("B=0000 before any bytes (got %0d)",
                                                field(ln, "B=", 4)));
        check(field(ln, "E=", 2) == 0, "E=00 before any bytes");
        check(field(ln, "S=", 1) >= 0, "S= field present and hex");
        check(field(ln, "F=", 1) >= 0, "F= field present and hex");
        check(field(ln, "A=", 1) >= 0, "A= field present and hex");
        check(field(ln, "N=", 2) == 0, "N=00: no MLP verdict yet");
        check(field(ln, "K=", 2) == 0, "K=00: no CNN verdict yet");
        check(field(ln, "M=", 1) == 2, "M=2 (Normal) is the pre-verdict default");

        // 0x55 and 0xFF have very different edge counts; a falling-edge counter
        // would disagree with the byte count here, a receiver will not.
        for (int i = 0; i < 20; i++) host_send(8'h55);
        for (int i = 0; i < 20; i++) host_send(8'hFF);
        for (int i = 0; i < 20; i++) host_send(8'h00);

        await_line(ln);                      // may have been mid-report
        await_line(ln);
        $display("  report 2: \"%s\"  (host sent %0d bytes)", ln, bytes_sent);
        b_field = field(ln, "B=", 4);
        check(b_field == bytes_sent,
              $sformatf("B counts bytes, not edges: want %0d, got %0d",
                        bytes_sent, b_field));

        for (int i = 0; i < 7; i++) host_send(8'hA5);
        await_line(ln);
        await_line(ln);
        $display("  report 3: \"%s\"  (host sent %0d bytes)", ln, bytes_sent);
        check(field(ln, "B=", 4) == bytes_sent,
              $sformatf("B keeps counting: want %0d, got %0d",
                        bytes_sent, field(ln, "B=", 4)));

        // ---- verdict strobes ------------------------------------------------
        // MLP: two one-cycle verdicts, class 1 (Misalign) then 3 (Unbalance).
        force dut.mlp_class = 2'd1;
        force dut.mlp_class_valid = 1'b1;  @(posedge clk);
        force dut.mlp_class_valid = 1'b0;  repeat (10) @(posedge clk);
        force dut.mlp_class = 2'd3;
        force dut.mlp_class_valid = 1'b1;  @(posedge clk);
        force dut.mlp_class_valid = 1'b0;
        // CNN: ONE verdict whose strobe is held for 5 cycles -- must count once.
        force dut.cnn_class = 2'd0;
        force dut.cnn_class_valid = 1'b1;  repeat (5) @(posedge clk);
        force dut.cnn_class_valid = 1'b0;
        repeat (4) @(posedge clk);
        release dut.mlp_class;  release dut.mlp_class_valid;
        release dut.cnn_class;  release dut.cnn_class_valid;

        await_line(ln);
        await_line(ln);
        $display("  report 4: \"%s\"", ln);
        check(field(ln, "N=", 2) == 2, $sformatf("N=02 after two MLP verdicts (got %0d)", field(ln, "N=", 2)));
        check(field(ln, "M=", 1) == 3, $sformatf("M=3: latest MLP class reported (got %0d)", field(ln, "M=", 1)));
        check(field(ln, "K=", 2) == 1, $sformatf("K=01: a held strobe counts once (got %0d)", field(ln, "K=", 2)));
        check(field(ln, "C=", 1) == 0, $sformatf("C=0: CNN class reported (got %0d)", field(ln, "C=", 1)));

        $display("=== %0d checks, %0d errors ===", checks, errors);
        if (errors == 0) $display("*** PASS ***");
        else             $display("*** FAIL ***");
        $finish;
    end

    initial begin
        #100ms;
        $display("*** FAIL *** global timeout");
        $fatal(1, "timeout");
    end

endmodule
