`timescale 1ns / 1ps

// ============================================================================
// uart_loopback_top -- board-level bring-up top for the USB-serial link
// ============================================================================
// Echoes every byte the host sends straight back to the host, so a terminal
// or Scripts/fpga_host/uart_loopback_test.py can prove the whole path:
//
//   host /dev/ttyUSB0 -> adapter TX -> GPIO_1[4] -> receiver -> elastic_fifo
//                     -> transmitter -> GPIO_0[4] -> adapter RX -> host
//
// None of the DSP/inference chain is instantiated. If this design does not
// echo, the fault is in the cabling, the pin assignment, the baud rate or the
// adapter -- never in the rest of the system. That is the whole point.
//
// >>> PIN_NOTE <<<
// The link is split across the two GPIO headers:
//   GPIO_1[4]  PIN_A13  JP2 pin 5   <- adapter TX   (this design's receive)
//   GPIO_0[4]  PIN_D17  JP1 pin 5   -> adapter RX   (this design's transmit)
//   GND                 JP1 pin 12  <- adapter GND
// A common ground is required and either header's GND will do, but the
// adapter needs one -- with the pair split across JP1 and JP2 it is easy to
// ground neither. Adapter TX goes to the FPGA's *RX* and vice versa; wiring
// TX->TX is the usual reason a loopback stays silent. Use a 3.3 V adapter:
// the DE0-CV GPIO banks are 3.3-V LVTTL and are not 5 V tolerant.
//
// >>> PORT_NAMING_NOTE <<<
// The two serial ports are declared as one-bit vectors indexed at 4 rather
// than as plain scalars, so the port name is literally GPIO_1[4] / GPIO_0[4]
// and the location assignments in uart_loopback.qsf can be copied verbatim
// from the DE0_CV.qsf board template. Only bit 4 of each header is brought
// out; the remaining GPIO pins stay unassigned and tri-stated.
//
// >>> ECHO_MODE_NOTE <<<
// A wire jumper between the adapter's own TX and RX pins also produces a
// perfect echo, so a passing byte-for-byte test does not by itself prove the
// FPGA is in the path. SW[0] high switches the echo to the bitwise complement
// of each byte, which only this design can produce. The host test drives both
// modes for exactly that reason.
//
// >>> THROUGHPUT_NOTE <<<
// transmitter.sv leaves TX_STATE_IDLE on the clock edge after tx_en goes low
// and only then waits for tx_clk_en, so holding tx_en low while the FIFO is
// non-empty sustains one byte every 10 bit periods -- the same rate the
// receiver delivers them. The FIFO therefore never fills from rate mismatch;
// it is here to cover the one-byte handover latency and any host burst.
// `overrun` on LEDR[8] is sticky and means bytes were genuinely lost.
// ============================================================================
module uart_loopback_top #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int OVERSAMPLE  = 16,
    parameter int FIFO_DEPTH  = 256,        // power of two, >= 2
    parameter int POR_CYCLES  = 1024,       // configuration-time reset stretch
    parameter int DEB_CYCLES  = CLK_FREQ_HZ / 50   // ~20 ms key debounce
)(
    input  logic       CLOCK_50,            // PIN_M9, 50 MHz oscillator
    input  logic [1:0] KEY,                 // active low: [0] reset, [1] send banner
    input  logic [9:0] SW,                  // SW[0]: 0 = echo, 1 = echo complement
    input  logic [4:4] GPIO_1,              // PIN_A13, JP2 pin 5, from adapter TX
    output logic [4:4] GPIO_0,              // PIN_D17, JP1 pin 5, to adapter RX
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,                // last received byte, low nibble
    output logic [6:0] HEX1,                // last received byte, high nibble
    output logic [6:0] HEX2,                // received-byte count, low nibble
    output logic [6:0] HEX3                 // received-byte count, high nibble
);

    logic clk;
    assign clk = CLOCK_50;

    // ------------------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------------------
    // Cyclone V registers come out of configuration cleared, which for
    // transmitter.sv means tx = 0 -- a held break on the line until something
    // asserts rst. The power-on counter below guarantees that happens ~20 us
    // after configuration, with no button press, so the board is usable the
    // moment it is programmed. KEY[0] then gives a manual reset on top.
    //
    // Declaration initialisers (not an `initial` block) set the power-up state:
    // Quartus honours them for Cyclone V and Verilator honours them in
    // simulation, so both agree on what happens before the first edge.
    localparam int POR_W = $clog2(POR_CYCLES);

    logic [POR_W:0] por_cnt = '0;
    logic           por_rst;

    assign por_rst = !por_cnt[POR_W];

    always_ff @(posedge clk) begin
        if (por_rst) por_cnt <= por_cnt + 1'b1;
    end

    // Two-flop synchroniser plus a ~20 ms debounce on the mechanical keys.
    // Deliberately not held in reset: it is what produces the reset. It starts
    // at 2'b11 because the keys are active low and an all-zero power-up state
    // would read as "both pressed".
    localparam int DEB_W = $clog2(DEB_CYCLES);

    logic [1:0]       key_meta  = 2'b11;
    logic [1:0]       key_sync  = 2'b11;
    logic [1:0]       key_deb   = 2'b11;
    logic [DEB_W-1:0] deb_cnt   = '0;

    always_ff @(posedge clk) begin
        key_meta <= KEY;
        key_sync <= key_meta;

        if (key_sync != key_deb) begin
            if (deb_cnt == DEB_W'(DEB_CYCLES - 1)) begin
                key_deb <= key_sync;
                deb_cnt <= '0;
            end else begin
                deb_cnt <= deb_cnt + 1'b1;
            end
        end else begin
            deb_cnt <= '0;
        end
    end

    logic rst;
    assign rst = por_rst || !key_deb[0];

    // ------------------------------------------------------------------------
    // Asynchronous inputs
    // ------------------------------------------------------------------------
    // GPIO_1[4] is free-running against clk and must be re-timed before it
    // reaches receiver.sv, which samples it directly. Three flops, matching
    // the synchroniser at the head of sensor_ingestion_subsystem.
    (* preserve *) logic [2:0] rx_sync_q;
    logic                      rx_sync;
    logic                      sw0_sync_q, sw0_sync;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_sync_q  <= 3'b111;       // idle line is high
            sw0_sync_q <= 1'b0;
            sw0_sync   <= 1'b0;
        end else begin
            rx_sync_q  <= {rx_sync_q[1:0], GPIO_1};
            sw0_sync_q <= SW[0];
            sw0_sync   <= sw0_sync_q;
        end
    end

    assign rx_sync = rx_sync_q[2];

    // ------------------------------------------------------------------------
    // UART core
    // ------------------------------------------------------------------------
    logic [7:0] rx_data;
    logic       rx_ready;
    logic       ready_clr;
    logic       tx_busy;

    logic [7:0] fifo_m_data;
    logic       fifo_m_valid;
    logic       fifo_m_ready;

    uart #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .OVERSAMPLE  (OVERSAMPLE)
    ) u_uart (
        .clk       (clk),
        .rst       (rst),
        // tx_en and rx_en are ACTIVE LOW in this core -- see transmitter.sv
        // and receiver.sv. Holding tx_en low while the FIFO has a byte is what
        // gives back-to-back transmission (THROUGHPUT_NOTE).
        .data_in   (fifo_m_data),
        .tx_en     (!fifo_m_valid),
        .tx        (GPIO_0),
        .tx_busy   (tx_busy),
        .rx        (rx_sync),
        .rx_en     (1'b0),
        .ready     (rx_ready),
        .ready_clr (ready_clr),
        .data_out  (rx_data)
    );

    // ------------------------------------------------------------------------
    // Receive -> FIFO
    // ------------------------------------------------------------------------
    // `ready` is a level the receiver holds until ready_clr. Turn it into a
    // one-cycle push and clear it in the same cycle: receiver.sv applies
    // ready_clr before the FSM may re-assert ready, so a byte arriving in that
    // same cycle is not lost.
    logic rx_ready_q;
    logic rx_push;

    always_ff @(posedge clk) begin
        if (rst) rx_ready_q <= 1'b0;
        else     rx_ready_q <= rx_ready;
    end

    assign rx_push   = rx_ready && !rx_ready_q;
    assign ready_clr = rx_push;

    // ------------------------------------------------------------------------
    // Banner injector -- proves the TX direction on its own
    // ------------------------------------------------------------------------
    // Pressing KEY[1] queues "UART OK\r\n". If the host sees it, then FPGA tx,
    // GPIO_0[4], the cable and the adapter's receiver all work, even when the
    // receive direction is dead. That splits a silent link into two halves.
    localparam int BANNER_LEN = 9;

    function automatic logic [7:0] banner_char(input logic [3:0] idx);
        case (idx)
            4'd0:    banner_char = 8'h55;   // 'U'
            4'd1:    banner_char = 8'h41;   // 'A'
            4'd2:    banner_char = 8'h52;   // 'R'
            4'd3:    banner_char = 8'h54;   // 'T'
            4'd4:    banner_char = 8'h20;   // ' '
            4'd5:    banner_char = 8'h4F;   // 'O'
            4'd6:    banner_char = 8'h4B;   // 'K'
            4'd7:    banner_char = 8'h0D;   // CR
            default: banner_char = 8'h0A;   // LF
        endcase
    endfunction

    logic       key1_q;
    logic       key1_press;
    logic       banner_run;
    logic [3:0] banner_idx;
    logic       banner_push;
    logic       fifo_s_ready;

    always_ff @(posedge clk) begin
        if (rst) key1_q <= 1'b1;
        else     key1_q <= key_deb[1];
    end

    assign key1_press = key1_q && !key_deb[1];      // active low: falling = press

    // rx_push wins the shared write port: the receiver cannot be back-pressured
    // and would drop the byte, while the banner can simply wait a cycle.
    assign banner_push = banner_run && !rx_push && fifo_s_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            banner_run <= 1'b0;
            banner_idx <= '0;
        end else if (key1_press && !banner_run) begin
            banner_run <= 1'b1;
            banner_idx <= '0;
        end else if (banner_push) begin
            banner_idx <= banner_idx + 1'b1;
            if (banner_idx == 4'(BANNER_LEN - 1)) banner_run <= 1'b0;
        end
    end

    // ------------------------------------------------------------------------
    // FIFO
    // ------------------------------------------------------------------------
    logic [7:0] echo_byte;
    logic [7:0] fifo_s_data;
    logic       fifo_s_valid;
    logic       fifo_overrun;

    // ECHO_MODE_NOTE: the transform is applied on the way in, so each byte
    // carries the mode it was received under and flipping SW[0] mid-stream
    // cannot re-label bytes already queued.
    assign echo_byte    = sw0_sync ? ~rx_data : rx_data;
    assign fifo_s_data  = rx_push ? echo_byte : banner_char(banner_idx);
    assign fifo_s_valid = rx_push || banner_push;

    elastic_fifo #(
        .WIDTH (8),
        .DEPTH (FIFO_DEPTH)
    ) u_fifo (
        .clk     (clk),
        .reset   (rst),
        .s_valid (fifo_s_valid),
        .s_ready (fifo_s_ready),
        .s_data  (fifo_s_data),
        .m_valid (fifo_m_valid),
        .m_ready (fifo_m_ready),
        .m_data  (fifo_m_data),
        .overrun (fifo_overrun),
        .level   ()
    );

    // The transmitter latches data_in on the edge it leaves TX_STATE_IDLE, and
    // tx_busy rises out of that same edge. Popping on the rising edge -- one
    // cycle later -- therefore retires the byte only after it has been captured.
    logic tx_busy_q;

    always_ff @(posedge clk) begin
        if (rst) tx_busy_q <= 1'b0;
        else     tx_busy_q <= tx_busy;
    end

    assign fifo_m_ready = tx_busy && !tx_busy_q;

    // ------------------------------------------------------------------------
    // Indicators
    // ------------------------------------------------------------------------
    localparam int ACT_CYCLES = CLK_FREQ_HZ / 20;   // ~50 ms, visible by eye
    localparam int ACT_W      = $clog2(ACT_CYCLES);

    logic [7:0]       last_byte;
    logic [7:0]       rx_count;
    logic [ACT_W-1:0] act_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            last_byte <= 8'h00;
            rx_count  <= 8'h00;
            act_cnt   <= '0;
        end else begin
            if (rx_push) begin
                last_byte <= rx_data;
                rx_count  <= rx_count + 1'b1;
                act_cnt   <= ACT_W'(ACT_CYCLES - 1);
            end else if (act_cnt != '0) begin
                act_cnt <= act_cnt - 1'b1;
            end
        end
    end

    assign LEDR[7:0] = last_byte;
    assign LEDR[8]   = fifo_overrun;        // sticky: bytes were lost
    assign LEDR[9]   = (act_cnt != '0);     // blinks with receive traffic

    function automatic logic [6:0] hex7seg(input logic [3:0] v);
        case (v)                            // active low, {g,f,e,d,c,b,a}
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

    assign HEX0 = hex7seg(last_byte[3:0]);
    assign HEX1 = hex7seg(last_byte[7:4]);
    assign HEX2 = hex7seg(rx_count[3:0]);
    assign HEX3 = hex7seg(rx_count[7:4]);

endmodule
