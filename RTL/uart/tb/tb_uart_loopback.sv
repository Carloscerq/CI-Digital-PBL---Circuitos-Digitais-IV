`timescale 1ns / 1ps

// ============================================================================
// tb_uart_loopback -- self-checking testbench for uart_loopback_top
// ============================================================================
// Plays the part of the host at the far end of the USB-serial adapter: it
// bit-bangs frames into GPIO_1[4] and decodes whatever comes back out of
// GPIO_0[4], exactly as pyserial does over /dev/ttyUSB0. Everything in between
// -- synchroniser, receiver, FIFO, transmitter -- is the DUT.
//
// Tests, in order:
//   t_idle_line       line idles high after configuration, with no reset press
//   t_echo_vectors    edge-case bytes come back unchanged        (SW[0] = 0)
//   t_invert_vectors  the same bytes come back complemented      (SW[0] = 1)
//   t_back_to_back    a gapless burst is echoed in order, nothing dropped
//   t_banner          KEY[1] emits "UART OK\r\n" with no receive traffic
//   t_reset_midframe  a reset during a frame does not wedge the link
//
// >>> TIMING_NOTE <<<
// Bit slots are counted in clk cycles rather than in absolute time. The baud
// divisor is exact by construction (CLK_FREQ_HZ / BAUD_RATE), so this keeps
// the stimulus edge-aligned with the DUT and removes any race between the
// testbench's notion of a bit period and the design's.
//
// >>> BAUD_NOTE <<<
// The default baud is deliberately far above the board's 115200: it shortens
// the run to seconds while exercising identical logic, since only the baud
// divisor changes. Use `--baud 115200` to run the production divisor.
// ============================================================================
module tb_uart_loopback #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 1_562_500,   // see BAUD_NOTE
    parameter int OVERSAMPLE  = 16
);

    localparam time CLK_PERIOD = 20ns;       // 50 MHz
    localparam int  BIT_CYCLES = CLK_FREQ_HZ / BAUD_RATE;
    localparam int  FIFO_DEPTH = 64;
    localparam int  POR_CYCLES = 16;         // shortened: 1024 only matters on silicon
    localparam int  DEB_CYCLES = 8;          // shortened: 20 ms of key bounce is not modelled

    localparam int  BURST_LEN  = 64;

    // ---------------------------------------------------------------- signals
    logic       clk = 1'b0;
    logic [1:0] key = 2'b11;                 // active low, released
    logic [9:0] sw  = '0;
    logic       uart_rxd = 1'b1;             // idle high
    logic       uart_txd;
    logic [9:0] ledr;
    logic [6:0] hex0, hex1, hex2, hex3;

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------------- DUT
    uart_loopback_top #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .OVERSAMPLE  (OVERSAMPLE),
        .FIFO_DEPTH  (FIFO_DEPTH),
        .POR_CYCLES  (POR_CYCLES),
        .DEB_CYCLES  (DEB_CYCLES)
    ) dut (
        .CLOCK_50 (clk),
        .KEY      (key),
        .SW       (sw),
        .GPIO_1   (uart_rxd),          // serial in,  PIN_A13
        .GPIO_0   (uart_txd),          // serial out, PIN_D17
        .LEDR     (ledr),
        .HEX0     (hex0),
        .HEX1     (hex1),
        .HEX2     (hex2),
        .HEX3     (hex3)
    );

    // -------------------------------------------------------------- scoring
    int errors   = 0;
    int checks   = 0;
    int framing_errors = 0;

    function automatic void check(input bit cond, input string what);
        checks++;
        if (!cond) begin
            errors++;
            $display("[%0t] FAIL: %s", $time, what);
        end
    endfunction

    // ------------------------------------------------------- host transmitter
    task automatic host_bit(input logic v);
        uart_rxd = v;
        repeat (BIT_CYCLES) @(posedge clk);
    endtask

    // One 8N1 frame. Consecutive calls produce a gapless stream, which is what
    // a host writing a block to the port actually does.
    task automatic host_send(input logic [7:0] b);
        host_bit(1'b0);
        for (int i = 0; i < 8; i++) host_bit(b[i]);
        host_bit(1'b1);
    endtask

    // ---------------------------------------------------------- host receiver
    // Free-running decoder: anything the DUT transmits lands in rx_q, so the
    // tests can assert on both what arrives and what does not.
    logic [7:0] rx_q [$];

    initial begin
        logic [7:0] b;
        forever begin
            @(negedge uart_txd);
            repeat (BIT_CYCLES/2) @(posedge clk);       // middle of the start bit
            if (uart_txd !== 1'b0) continue;            // edge was not a start bit
            for (int i = 0; i < 8; i++) begin
                repeat (BIT_CYCLES) @(posedge clk);
                b[i] = uart_txd;
            end
            repeat (BIT_CYCLES) @(posedge clk);
            if (uart_txd !== 1'b1) begin
                framing_errors++;
                $display("[%0t] FAIL: stop bit low after byte %02h", $time, b);
            end
            rx_q.push_back(b);
        end
    end

    // Waits for one echoed byte, or gives up after a generous timeout.
    task automatic expect_byte(input logic [7:0] want, input string what);
        int guard = 0;
        while (rx_q.size() == 0 && guard < 40 * BIT_CYCLES) begin
            @(posedge clk);
            guard++;
        end
        if (rx_q.size() == 0) begin
            errors++;
            checks++;
            $display("[%0t] FAIL: %s -- timed out waiting for %02h", $time, what, want);
        end else begin
            logic [7:0] got = rx_q.pop_front();
            check(got == want, $sformatf("%s -- want %02h, got %02h", what, want, got));
        end
    endtask

    task automatic idle_bits(input int n);
        uart_rxd = 1'b1;
        repeat (n * BIT_CYCLES) @(posedge clk);
    endtask

    // ------------------------------------------------------------------ tests
    localparam logic [7:0] VECTORS [0:7] = '{
        8'h00, 8'hFF, 8'h55, 8'hAA, 8'h01, 8'h80, 8'h5A, 8'hA5
    };

    // The line must be high on its own, without a reset press: transmitter.sv
    // powers up with tx = 0, and only the internal power-on reset lifts it.
    // If this fails on hardware the host sees a permanent break condition.
    task automatic t_idle_line();
        repeat (4 * POR_CYCLES) @(posedge clk);
        check(uart_txd === 1'b1, "TX idles high after power-on reset, no button press");
        check(rx_q.size() == 0,  "nothing transmitted before any byte arrives");
    endtask

    task automatic t_echo_vectors();
        sw[0] = 1'b0;
        idle_bits(2);
        foreach (VECTORS[i]) begin
            host_send(VECTORS[i]);
            expect_byte(VECTORS[i], $sformatf("echo of %02h", VECTORS[i]));
        end
        check(ledr[7:0] == VECTORS[$size(VECTORS)-1], "LEDR shows the last byte received");
        check(ledr[8] == 1'b0, "no FIFO overrun during the vector echo");
    endtask

    // ECHO_MODE_NOTE in the RTL: this is the mode a plain TX-RX jumper on the
    // adapter cannot reproduce, so it is what proves the FPGA is in the path.
    task automatic t_invert_vectors();
        sw[0] = 1'b1;
        idle_bits(4);                     // let the SW synchroniser settle
        foreach (VECTORS[i]) begin
            host_send(VECTORS[i]);
            expect_byte(~VECTORS[i], $sformatf("complement of %02h", VECTORS[i]));
        end
        sw[0] = 1'b0;
        idle_bits(4);
    endtask

    // The real question this testbench exists to answer: with the host writing
    // a block at full rate and no gaps, does every byte come back, in order?
    task automatic t_back_to_back();
        logic [7:0] sent [$];
        int got_count = 0;

        rx_q.delete();
        idle_bits(2);

        for (int i = 0; i < BURST_LEN; i++) begin
            logic [7:0] b = 8'(i * 7 + 3);
            sent.push_back(b);
            host_send(b);                 // no idle between frames
        end

        // Drain: the FIFO lags the burst by roughly one frame.
        repeat (20 * BIT_CYCLES) @(posedge clk);

        check(rx_q.size() == BURST_LEN,
              $sformatf("all %0d burst bytes echoed (got %0d)", BURST_LEN, rx_q.size()));

        got_count = rx_q.size() < BURST_LEN ? rx_q.size() : BURST_LEN;
        for (int i = 0; i < got_count; i++) begin
            logic [7:0] got = rx_q.pop_front();
            check(got == sent[i], $sformatf("burst byte %0d -- want %02h, got %02h",
                                            i, sent[i], got));
        end

        check(ledr[8] == 1'b0, "no FIFO overrun across a gapless burst");
        rx_q.delete();
    endtask

    // KEY[1] must produce output with nothing arriving on the receive side --
    // that is what isolates a dead TX from a dead RX on the bench.
    task automatic t_banner();
        localparam logic [7:0] BANNER [0:8] = '{
            8'h55, 8'h41, 8'h52, 8'h54, 8'h20, 8'h4F, 8'h4B, 8'h0D, 8'h0A
        };

        rx_q.delete();
        key[1] = 1'b0;                                  // press
        repeat (4 * DEB_CYCLES) @(posedge clk);
        key[1] = 1'b1;                                  // release
        repeat (4 * DEB_CYCLES) @(posedge clk);

        foreach (BANNER[i]) expect_byte(BANNER[i], $sformatf("banner char %0d", i));

        idle_bits(2);
        check(rx_q.size() == 0, "banner sent exactly once per press");
    endtask

    // A reset landing mid-frame must not leave the receiver stuck waiting for
    // bits that will never come; the next clean byte has to get through.
    task automatic t_reset_midframe();
        rx_q.delete();
        fork
            host_send(8'h3C);
            begin
                repeat (5 * BIT_CYCLES) @(posedge clk);
                key[0] = 1'b0;                          // press reset
                repeat (4 * DEB_CYCLES) @(posedge clk);
                key[0] = 1'b1;
                repeat (4 * DEB_CYCLES) @(posedge clk);
            end
        join

        // The receiver resynchronises on the next start edge, so the torn frame
        // is charged one garbage byte -- it latches whatever bits followed the
        // reset. Wait for that to work its way out through the FIFO and the
        // transmitter before judging recovery, rather than racing it.
        idle_bits(30);
        check(rx_q.size() <= 1, $sformatf(
              "a mid-frame reset costs at most the torn byte (saw %0d)", rx_q.size()));
        rx_q.delete();

        host_send(8'hC3);
        expect_byte(8'hC3, "link recovers after a mid-frame reset");
    endtask

    // ------------------------------------------------------------------- main
    initial begin
        $display("=== tb_uart_loopback: %0d baud, %0d clk/bit ===", BAUD_RATE, BIT_CYCLES);

        t_idle_line();
        t_echo_vectors();
        t_invert_vectors();
        t_back_to_back();
        t_banner();
        t_reset_midframe();

        errors += framing_errors;
        $display("=== %0d checks, %0d errors, %0d framing errors ===",
                 checks, errors, framing_errors);
        if (errors == 0) $display("*** PASS ***");
        else             $display("*** FAIL ***");
        $finish;
    end

    // Watchdog: a wedged link would otherwise hang the run rather than fail it.
    initial begin
        #50ms;
        $display("*** FAIL *** global timeout");
        $fatal(1, "timeout");
    end

endmodule
