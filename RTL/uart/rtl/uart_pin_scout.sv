`timescale 1ns / 1ps

// ============================================================================
// uart_pin_scout -- finds which GPIO pins the USB-serial adapter is on
// ============================================================================
// A bring-up aid, not part of the system. When the loopback is silent and the
// wiring is in doubt, this replaces guess-and-recompile with one measurement.
//
// It works both directions at once:
//
//   TRANSMIT  Three candidate output pins each beacon a 14-byte message that
//             names themselves, continuously at 115200 8N1:
//                 "TX=D17 RX=xx\r\n"   GPIO_0[4]   PIN_D17
//                 "TX=N21 RX=xx\r\n"   GPIO_0[10]  PIN_N21  (the pin
//                                      Scripts/.../UART-Teste drives)
//                 "TX=B16 RX=xx\r\n"   GPIO_0[1]   PIN_B16
//             Only the pin actually wired to the adapter's RX reaches the
//             host, so whatever the host prints names the pin.
//
//   RECEIVE   Every other GPIO pin is an input with a weak pull-up, so an
//             unconnected pin reads high and only a pin being driven low can
//             register. The first one seen low is latched and its index is
//             reported as the "xx" field above, and on LEDR/HEX. Send any
//             bytes from the host and the start bits give it away.
//
// >>> INDEX_NOTE <<<
// xx is hex: 00..23 are GPIO_0[0..35], 24..47 are GPIO_1[0..35]. "--" means
// nothing has been seen low yet. KEY[0] clears the latch.
//
// >>> CONTENTION_NOTE <<<
// The three beacon pins are driven; every other pin is tri-stated. They are
// all on GPIO_0 and are meant to feed the adapter's RX input, which never
// drives back. Drive strength is held to 4 mA in the qsf so that a wiring
// mistake that did put an output against a driver stays a mild one.
// ============================================================================
module uart_pin_scout #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200
)(
    input  logic        CLOCK_50,
    input  logic [1:0]  KEY,                // KEY[0] clears the latched index
    inout  logic [35:0] GPIO_0,             // 3 bits beacon, the rest listen
    input  logic [35:0] GPIO_1,             // all listen
    output logic [9:0]  LEDR,
    output logic [6:0]  HEX0,
    output logic [6:0]  HEX1
);

    logic clk;
    assign clk = CLOCK_50;

    // ------------------------------------------------------------------ reset
    logic [10:0] por_cnt = '0;
    logic        por_rst;
    assign por_rst = !por_cnt[10];
    always_ff @(posedge clk) if (por_rst) por_cnt <= por_cnt + 1'b1;

    logic [1:0] key_meta = 2'b11, key_sync = 2'b11;
    always_ff @(posedge clk) begin
        key_meta <= KEY;
        key_sync <= key_meta;
    end

    logic clear_latch;
    assign clear_latch = por_rst || !key_sync[0];

    // -------------------------------------------------------------- baud tick
    localparam int DIV = CLK_FREQ_HZ / BAUD_RATE;

    logic [$clog2(DIV)-1:0] div_cnt = '0;
    logic                   baud_tick;

    assign baud_tick = (div_cnt == $clog2(DIV)'(DIV - 1));

    always_ff @(posedge clk) begin
        if (baud_tick) div_cnt <= '0;
        else           div_cnt <= div_cnt + 1'b1;
    end

    // --------------------------------------------------- shared frame timing
    // Every beacon sends the same 14-byte shape at the same instant and
    // differs only in three characters, so one counter drives all of them.
    localparam int MSG_LEN  = 14;
    localparam int IDLE_PAD = 2;            // idle byte slots between repeats

    logic [3:0] bit_idx  = '0;              // 0 start, 1..8 data, 9 stop
    logic [4:0] byte_idx = '0;              // 0..MSG_LEN-1, then idle

    always_ff @(posedge clk) begin
        if (baud_tick) begin
            if (bit_idx == 4'd9) begin
                bit_idx <= '0;
                byte_idx <= (byte_idx == 5'(MSG_LEN + IDLE_PAD - 1))
                            ? 5'd0 : byte_idx + 1'b1;
            end else begin
                bit_idx <= bit_idx + 1'b1;
            end
        end
    end

    // ------------------------------------------------------- pin observation
    // Driven bits are forced high in the observed vector so a beacon's own
    // start bits can never be mistaken for the adapter.
    logic [35:0] gpio0_obs;
    logic [71:0] pin_raw, pin_meta = '1, pin_sync = '1, pin_low = '0;

    always_comb begin
        gpio0_obs = GPIO_0;
        gpio0_obs[1]  = 1'b1;
        gpio0_obs[4]  = 1'b1;
        gpio0_obs[10] = 1'b1;
    end

    assign pin_raw = {GPIO_1, gpio0_obs};

    // >>> QUALIFY_NOTE <<<
    // A pin qualifies only after EDGE_TARGET separate falling edges, not after
    // one low sample. A floating pin that picks up a single glitch, or a header
    // pin wired to something unrelated, would otherwise latch first and -- with
    // lowest-index-wins below -- permanently mask the pin actually carrying
    // data. The adapter's TX produces one falling edge per byte sent, so a
    // handful of bytes from the host clears the bar immediately.
    localparam int EDGE_TARGET = 15;

    logic [71:0]      pin_fall;
    logic [71:0]      qualified;
    logic [3:0]       edge_cnt [0:71];

    assign pin_fall = pin_meta & ~pin_sync;      // one-cycle falling edge per pin

    always_ff @(posedge clk) begin
        pin_meta <= pin_raw;
        pin_sync <= pin_meta;
        if (clear_latch) pin_low <= '0;
        else             pin_low <= pin_low | ~pin_sync;
    end

    always_ff @(posedge clk) begin
        for (int i = 0; i < 72; i++) begin
            if (clear_latch)
                edge_cnt[i] <= '0;
            else if (pin_fall[i] && edge_cnt[i] != 4'(EDGE_TARGET))
                edge_cnt[i] <= edge_cnt[i] + 1'b1;
        end
    end

    always_comb begin
        for (int i = 0; i < 72; i++) qualified[i] = (edge_cnt[i] == 4'(EDGE_TARGET));
    end

    // Lowest qualifying index wins, so a single connected pin reports
    // unambiguously once it has proven itself.
    logic       found;
    logic [6:0] found_idx;

    always_comb begin
        found     = 1'b0;
        found_idx = 7'd0;
        for (int i = 71; i >= 0; i--) begin
            if (qualified[i]) begin
                found     = 1'b1;
                found_idx = 7'(i);
            end
        end
    end

    // ------------------------------------------------------------- characters
    function automatic logic [7:0] hexchar(input logic [3:0] v);
        hexchar = (v < 4'd10) ? (8'h30 + 8'(v)) : (8'h41 + 8'(v) - 8'd10);
    endfunction

    logic [7:0] rx_hi, rx_lo;
    assign rx_hi = found ? hexchar({1'b0, found_idx[6:4]}) : 8'h2D;   // '-'
    assign rx_lo = found ? hexchar(found_idx[3:0])         : 8'h2D;

    // "TX=" c0 c1 c2 " RX=" hi lo CR LF
    function automatic logic [7:0] msg_byte(input logic [7:0] c0,
                                            input logic [7:0] c1,
                                            input logic [7:0] c2,
                                            input logic [4:0] bi);
        case (bi)
            5'd0:    msg_byte = 8'h54;      // 'T'
            5'd1:    msg_byte = 8'h58;      // 'X'
            5'd2:    msg_byte = 8'h3D;      // '='
            5'd3:    msg_byte = c0;
            5'd4:    msg_byte = c1;
            5'd5:    msg_byte = c2;
            5'd6:    msg_byte = 8'h20;      // ' '
            5'd7:    msg_byte = 8'h52;      // 'R'
            5'd8:    msg_byte = 8'h58;      // 'X'
            5'd9:    msg_byte = 8'h3D;      // '='
            5'd10:   msg_byte = rx_hi;
            5'd11:   msg_byte = rx_lo;
            5'd12:   msg_byte = 8'h0D;      // CR
            default: msg_byte = 8'h0A;      // LF
        endcase
    endfunction

    function automatic logic serial_bit(input logic [7:0] c0,
                                        input logic [7:0] c1,
                                        input logic [7:0] c2);
        logic [7:0] b;
        b = msg_byte(c0, c1, c2, byte_idx);
        if (byte_idx >= 5'(MSG_LEN)) serial_bit = 1'b1;          // idle
        else if (bit_idx == 4'd0)    serial_bit = 1'b0;          // start
        else if (bit_idx == 4'd9)    serial_bit = 1'b1;          // stop
        else                         serial_bit = b[bit_idx - 1];
    endfunction

    logic tx_d17, tx_n21, tx_b16;

    always_ff @(posedge clk) begin
        if (por_rst) begin
            tx_d17 <= 1'b1;
            tx_n21 <= 1'b1;
            tx_b16 <= 1'b1;
        end else begin
            tx_d17 <= serial_bit(8'h44, 8'h31, 8'h37);   // "D17"
            tx_n21 <= serial_bit(8'h4E, 8'h32, 8'h31);   // "N21"
            tx_b16 <= serial_bit(8'h42, 8'h31, 8'h36);   // "B16"
        end
    end

    // ------------------------------------------------------------ pin drivers
    // Explicit slices rather than a generate loop: Quartus's parser rejects an
    // inline `for (genvar ...)` here, and spelling the three driven bits out
    // makes it obvious at a glance which pins are outputs.
    assign GPIO_0[35:11] = 25'bz;
    assign GPIO_0[10]    = tx_n21;
    assign GPIO_0[9:5]   = 5'bz;
    assign GPIO_0[4]     = tx_d17;
    assign GPIO_0[3:2]   = 2'bz;
    assign GPIO_0[1]     = tx_b16;
    assign GPIO_0[0]     = 1'bz;

    // ------------------------------------------------------------- indicators
    assign LEDR[6:0] = found_idx;
    assign LEDR[7]   = 1'b0;
    assign LEDR[8]   = |pin_low;    // any pin seen low at all, even once
    assign LEDR[9]   = found;

    function automatic logic [6:0] hex7seg(input logic [3:0] v);
        case (v)
            4'h0:    hex7seg = 7'b1000000;
            4'h1:    hex7seg = 7'b1111001;
            4'h2:    hex7seg = 7'b0100100;
            4'h3:    hex7seg = 7'b0110000;
            4'h4:    hex7seg = 7'b0011001;
            4'h5:    hex7seg = 7'b0010010;
            4'h6:    hex7seg = 7'b0000010;
            4'h7:    hex7seg = 7'b1111000;
            4'h8:    hex7seg = 7'b0000000;
            4'h9:    hex7seg = 7'b0010000;
            4'hA:    hex7seg = 7'b0001000;
            4'hB:    hex7seg = 7'b0000011;
            4'hC:    hex7seg = 7'b1000110;
            4'hD:    hex7seg = 7'b0100001;
            4'hE:    hex7seg = 7'b0000110;
            default: hex7seg = 7'b0001110;
        endcase
    endfunction

    assign HEX0 = found ? hex7seg(found_idx[3:0])        : 7'b0111111;  // '-'
    assign HEX1 = found ? hex7seg({1'b0, found_idx[6:4]}) : 7'b0111111;

endmodule
