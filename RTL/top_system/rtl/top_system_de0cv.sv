`timescale 1ns / 1ps

// ============================================================================
// top_system_de0cv -- board wrapper: DE0-CV pins onto top_system
// ============================================================================
// top_system talks in logical names (clk, reset, uart_rx, status_leds, ...) so
// tb_top_system can drive it and so it stays portable. Everything specific to
// this board lives here: the pin names, the reset scheme, the input
// synchroniser, and the packing of 14 status bits onto 10 LEDs and 4 digits.
//
// >>> PIN_NAMING_NOTE <<<
// The ports are named after DE0-CV board signals, so the pin table already in
// RTL/quartus/quartus.qsf (copied from the Terasic DE0_CV.qsf template)
// applies unchanged -- no new location assignments are needed for CLOCK_50,
// SW, KEY, LEDR or HEX. The one serial pin is declared as a one-bit vector
// indexed at 4 so its port name is literally GPIO_1[4], matching the
// template's own line. Same trick as uart_loopback_top.
//
// >>> WHY_GPIO_1 <<<
// The sensor stream arrives on GPIO_1[4] = PIN_A13, which is where the
// CP2102's TX is landed and what uart_loopback_top proved working. GPIO_0[4]
// = PIN_D17 is the other half of that link -- the FPGA's transmit pin, driven
// by the adapter's RX input, which never drives back. Listening on D17 would
// hear nothing, so this is the port to get right.
//
// >>> TELEMETRY_NOTE <<<
// top_system has no UART transmitter: its verdicts come out on LEDs only, and
// Scripts/fpga_host never reads from the port, so streaming is entirely
// open-loop -- the host cannot tell whether the board received a single byte.
// This wrapper closes that loop. A snooping receiver counts bytes on the line,
// and a transmitter on GPIO_0[4] (PIN_D17, the other half of the link
// uart_loopback_top proved) reports every TELEM_PERIOD_CYCLES:
//
//     B=xxxx E=xx S=x F=x A=x M=c N=xx C=c K=xx\r\n
//
//   B  bytes seen on the wire, 16-bit, wraps          (hex)
//   E  error_status, sticky, one bit per fault source (hex, 6 bits)
//   S  status_leds: [2] Critical [1] Warning [0] Normal
//   F  sensor_fault_mask, one bit per vibration channel
//   A  alert_flag
//   M  class of the most recent MLP verdict  (0 Bearing 1 Misalign
//   C  class of the most recent CNN verdict   2 Normal  3 Unbalance)
//   N  MLP verdicts so far, 8-bit, wraps -- a change means a new verdict
//   K  CNN verdicts so far, 8-bit, wraps
//
// M and C are only meaningful once N / K are non-zero. The counters exist so
// the host can score each verdict exactly once instead of re-counting the same
// latched class every report.
//
// B counts at the wire, independent of framing, so it separates "no bytes are
// arriving" from "bytes arrive but the frames are rejected" -- which is E's
// bit 0. The same values are on the LEDs and digits for when no host is
// attached.
// ============================================================================
module top_system_de0cv #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int FIFO_DEPTH  = 64,
    parameter int POR_CYCLES  = 1024,       // configuration-time reset stretch
    parameter int TELEM_PERIOD_CYCLES = CLK_FREQ_HZ / 2   // ~500 ms between reports
)(
    input  logic       CLOCK_50,            // PIN_M9, 50 MHz oscillator
    input  logic [0:0] KEY,                 // active low; KEY[0] = manual reset
    input  logic [0:0] SW,                  // SW[0] = hold reset (active high)
    input  logic [4:4] GPIO_1,              // PIN_A13, sensor stream in
    output logic [4:4] GPIO_0,              // PIN_D17, telemetry out
    output logic [9:0] LEDR,
    output logic [6:0] HEX0,                // error_status, low nibble
    output logic [6:0] HEX1,                // error_status, high bits
    output logic [6:0] HEX2,                // serial byte count, low nibble
    output logic [6:0] HEX3                 // serial byte count, high nibble
);

    import system_types_pkg::*;

    logic clk;
    assign clk = CLOCK_50;

    // ------------------------------------------------------------------------
    // Reset
    // ------------------------------------------------------------------------
    // top_system's reset is SYNCHRONOUS and ACTIVE HIGH. Three sources are
    // OR-ed: a power-on stretch so the design starts from a known state the
    // moment it is configured, KEY[0] for a momentary reset, and SW[0] for a
    // held one. Without the power-on term the chain would come out of
    // configuration with every register cleared and nothing ever asserting
    // reset, which leaves the sticky error bus and the FSMs in whatever state
    // the fitter's power-up gave them.
    localparam int POR_W = $clog2(POR_CYCLES);

    logic [POR_W:0] por_cnt = '0;
    logic           por_rst;

    assign por_rst = !por_cnt[POR_W];

    always_ff @(posedge clk) begin
        if (por_rst) por_cnt <= por_cnt + 1'b1;
    end

    // KEY and SW are mechanical; two flops each. Started at the released state
    // because an all-zero power-up would read KEY as pressed.
    logic [0:0] key_meta = 1'b1,  key_sync = 1'b1;
    logic [0:0] sw_meta  = 1'b0,  sw_sync  = 1'b0;

    always_ff @(posedge clk) begin
        key_meta <= KEY;
        key_sync <= key_meta;
        sw_meta  <= SW;
        sw_sync  <= sw_meta;
    end

    logic reset;
    assign reset = por_rst || !key_sync[0] || sw_sync[0];

    // ------------------------------------------------------------------------
    // Serial input
    // ------------------------------------------------------------------------
    // The line is free-running against clk. sensor_ingestion_subsystem has its
    // own synchroniser at the head, but re-timing here as well costs three
    // flops and means the byte counter below and the design proper see exactly
    // the same signal.
    logic [2:0] rx_sync_q;
    logic       rx_sync;

    always_ff @(posedge clk) begin
        if (reset) rx_sync_q <= 3'b111;     // idle line is high
        else       rx_sync_q <= {rx_sync_q[1:0], GPIO_1[4]};
    end

    assign rx_sync = rx_sync_q[2];

    // ------------------------------------------------------------------------
    // Wire-level byte counter -- see NO_TRANSMIT_NOTE
    // ------------------------------------------------------------------------
    // A second receiver listening to the same line, purely to count bytes. It
    // is read-only and completely independent of the ingestion path, so the
    // count keeps advancing even when framing or the checksum is rejecting
    // everything downstream -- which is the whole point: it separates "no bytes
    // are arriving" from "bytes arrive but the frames are wrong".
    //
    // Counting falling edges instead would have been cheaper and wrong: the
    // line idles high but data bits toggle freely, so 0x55 yields four falling
    // edges and 0xFF yields one. Only a receiver knows where frames start.
    localparam int SNOOP_OVERSAMPLE = 16;

    logic snoop_rx_clk_en, snoop_tx_clk_en;
    logic snoop_ready, snoop_ready_q, snoop_byte_done;
    logic [7:0] snoop_data;

    baudrate #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE),
        .OVERSAMPLE  (SNOOP_OVERSAMPLE)
    ) u_snoop_baud (
        .clk       (clk),
        .rst       (reset),
        .rx_clk_en (snoop_rx_clk_en),
        .tx_clk_en (snoop_tx_clk_en)       // 1x tick, drives the telemetry tx
    );

    receiver #(
        .OVERSAMPLE (SNOOP_OVERSAMPLE)
    ) u_snoop_rx (
        .clk       (clk),
        .rst       (reset),
        .clk_en    (snoop_rx_clk_en),
        .rx        (rx_sync),
        .rx_en     (1'b0),                 // active low: always enabled
        .ready_clr (snoop_byte_done),
        .ready     (snoop_ready),
        .data      (snoop_data)
    );

    // `ready` is a level held until ready_clr; turn it into one pulse per byte.
    assign snoop_byte_done = snoop_ready && !snoop_ready_q;

    logic [15:0] byte_count;               // wraps at 65536; a liveness dial
    logic [$clog2(CLK_FREQ_HZ / 20)-1:0] act_cnt;

    always_ff @(posedge clk) begin
        if (reset) begin
            snoop_ready_q <= 1'b0;
            byte_count    <= '0;
            act_cnt       <= '0;
        end else begin
            snoop_ready_q <= snoop_ready;
            if (snoop_byte_done) begin
                byte_count <= byte_count + 1'b1;
                act_cnt    <= '1;
            end else if (act_cnt != '0) begin
                act_cnt <= act_cnt - 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // The design
    // ------------------------------------------------------------------------
    logic [2:0]          status_leds;
    logic [N_VIB-1:0]    sensor_fault_mask;
    logic                alert_flag;
    error_status_t       error_status;
    logic [1:0]          mlp_class, cnn_class;
    logic                mlp_class_valid, cnn_class_valid;

    top_system #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_top_system (
        .clk              (clk),
        .reset            (reset),
        .uart_rx          (rx_sync),
        .status_leds      (status_leds),
        .sensor_fault_mask(sensor_fault_mask),
        .alert_flag       (alert_flag),
        .error_status     (error_status),
        .mlp_class        (mlp_class),
        .mlp_class_valid  (mlp_class_valid),
        .cnn_class        (cnn_class),
        .cnn_class_valid  (cnn_class_valid)
    );

    // Latch each verdict and count them. Counting rising edges rather than
    // strobe-high cycles makes the count right whether a strobe is a one-cycle
    // pulse or a level held for a handshake.
    logic       mlp_v_q, cnn_v_q;
    logic [1:0] last_mlp, last_cnn;
    logic [7:0] n_mlp, n_cnn;

    always_ff @(posedge clk) begin
        if (reset) begin
            mlp_v_q  <= 1'b0;
            cnn_v_q  <= 1'b0;
            last_mlp <= 2'd2;               // Normal, as the arbiter defaults
            last_cnn <= 2'd2;
            n_mlp    <= '0;
            n_cnn    <= '0;
        end else begin
            mlp_v_q <= mlp_class_valid;
            cnn_v_q <= cnn_class_valid;
            if (mlp_class_valid && !mlp_v_q) begin
                last_mlp <= mlp_class;
                n_mlp    <= n_mlp + 1'b1;
            end
            if (cnn_class_valid && !cnn_v_q) begin
                last_cnn <= cnn_class;
                n_cnn    <= n_cnn + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------------
    // Telemetry transmitter -- see TELEMETRY_NOTE
    // ------------------------------------------------------------------------
    // The values are latched when a report starts, so the digits in one line
    // are a single coherent snapshot rather than a smear across the 25 byte
    // times it takes to send.
    localparam int TELEM_LEN = 43;          // "B=xxxx E=xx S=x F=x A=x M=c N=xx C=c K=xx\r\n"
    localparam int TELEM_W   = $clog2(TELEM_PERIOD_CYCLES);

    logic [TELEM_W-1:0] telem_cnt;
    logic               telem_tick;

    assign telem_tick = (telem_cnt == TELEM_W'(TELEM_PERIOD_CYCLES - 1));

    always_ff @(posedge clk) begin
        if (reset)           telem_cnt <= '0;
        else if (telem_tick) telem_cnt <= '0;
        else                 telem_cnt <= telem_cnt + 1'b1;
    end

    logic [15:0]      snap_bytes;
    error_status_t    snap_err;
    logic [2:0]       snap_status;
    logic [N_VIB-1:0] snap_fault;
    logic             snap_alert;
    logic [1:0]       snap_mlp, snap_cnn;
    logic [7:0]       snap_n_mlp, snap_n_cnn;

    function automatic logic [7:0] hexchar(input logic [3:0] v);
        hexchar = (v < 4'd10) ? (8'h30 + 8'(v)) : (8'h41 + 8'(v) - 8'd10);
    endfunction

    function automatic logic [7:0] telem_byte(input logic [5:0] i);
        case (i)
            6'd0:  telem_byte = 8'h42;                    // 'B'
            6'd1:  telem_byte = 8'h3D;                    // '='
            6'd2:  telem_byte = hexchar(snap_bytes[15:12]);
            6'd3:  telem_byte = hexchar(snap_bytes[11:8]);
            6'd4:  telem_byte = hexchar(snap_bytes[7:4]);
            6'd5:  telem_byte = hexchar(snap_bytes[3:0]);
            6'd6:  telem_byte = 8'h20;                    // ' '
            6'd7:  telem_byte = 8'h45;                    // 'E'
            6'd8:  telem_byte = 8'h3D;
            6'd9:  telem_byte = hexchar({2'b00, snap_err[5:4]});
            6'd10: telem_byte = hexchar(snap_err[3:0]);
            6'd11: telem_byte = 8'h20;
            6'd12: telem_byte = 8'h53;                    // 'S'
            6'd13: telem_byte = 8'h3D;
            6'd14: telem_byte = hexchar({1'b0, snap_status});
            6'd15: telem_byte = 8'h20;
            6'd16: telem_byte = 8'h46;                    // 'F'
            6'd17: telem_byte = 8'h3D;
            6'd18: telem_byte = hexchar(snap_fault);
            6'd19: telem_byte = 8'h20;
            6'd20: telem_byte = 8'h41;                    // 'A'
            6'd21: telem_byte = 8'h3D;
            6'd22: telem_byte = hexchar({3'b000, snap_alert});
            6'd23: telem_byte = 8'h20;
            6'd24: telem_byte = 8'h4D;                    // 'M'
            6'd25: telem_byte = 8'h3D;
            6'd26: telem_byte = hexchar({2'b00, snap_mlp});
            6'd27: telem_byte = 8'h20;
            6'd28: telem_byte = 8'h4E;                    // 'N'
            6'd29: telem_byte = 8'h3D;
            6'd30: telem_byte = hexchar(snap_n_mlp[7:4]);
            6'd31: telem_byte = hexchar(snap_n_mlp[3:0]);
            6'd32: telem_byte = 8'h20;
            6'd33: telem_byte = 8'h43;                    // 'C'
            6'd34: telem_byte = 8'h3D;
            6'd35: telem_byte = hexchar({2'b00, snap_cnn});
            6'd36: telem_byte = 8'h20;
            6'd37: telem_byte = 8'h4B;                    // 'K'
            6'd38: telem_byte = 8'h3D;
            6'd39: telem_byte = hexchar(snap_n_cnn[7:4]);
            6'd40: telem_byte = hexchar(snap_n_cnn[3:0]);
            6'd41: telem_byte = 8'h0D;                    // CR
            default: telem_byte = 8'h0A;                  // LF
        endcase
    endfunction

    // transmitter.sv latches data_in on the edge it leaves TX_STATE_IDLE and
    // raises tx_busy out of that same edge, so holding tx_req through the
    // busy-rising handshake is what guarantees the byte was captured before the
    // index advances. tx_en is ACTIVE LOW -- see transmitter.sv.
    typedef enum logic [1:0] {
        T_IDLE = 2'b00,
        T_LOAD = 2'b01,
        T_BUSY = 2'b10,
        T_DONE = 2'b11
    } telem_state_e;

    telem_state_e telem_state;
    logic [5:0]   telem_idx;
    logic         telem_req;
    logic         telem_tx_busy;

    always_ff @(posedge clk) begin
        if (reset) begin
            telem_state <= T_IDLE;
            telem_idx   <= '0;
            telem_req   <= 1'b0;
            snap_bytes  <= '0;
            snap_err    <= '0;
            snap_status <= '0;
            snap_fault  <= '0;
            snap_alert  <= 1'b0;
            snap_mlp    <= 2'd2;
            snap_cnn    <= 2'd2;
            snap_n_mlp  <= '0;
            snap_n_cnn  <= '0;
        end else begin
            case (telem_state)
                T_IDLE: if (telem_tick) begin
                    snap_bytes  <= byte_count;
                    snap_err    <= error_status;
                    snap_status <= status_leds;
                    snap_fault  <= sensor_fault_mask;
                    snap_alert  <= alert_flag;
                    snap_mlp    <= last_mlp;
                    snap_cnn    <= last_cnn;
                    snap_n_mlp  <= n_mlp;
                    snap_n_cnn  <= n_cnn;
                    telem_idx   <= '0;
                    telem_state <= T_LOAD;
                end

                T_LOAD: begin
                    telem_req   <= 1'b1;
                    telem_state <= T_BUSY;
                end

                T_BUSY: if (telem_tx_busy) begin
                    telem_req   <= 1'b0;      // byte captured; release
                    telem_state <= T_DONE;
                end

                T_DONE: if (!telem_tx_busy) begin
                    if (telem_idx == 6'(TELEM_LEN - 1)) begin
                        telem_state <= T_IDLE;
                    end else begin
                        telem_idx   <= telem_idx + 1'b1;
                        telem_state <= T_LOAD;
                    end
                end

                default: telem_state <= T_IDLE;
            endcase
        end
    end

    transmitter u_telem_tx (
        .clk     (clk),
        .rst     (reset),
        .clk_en  (snoop_tx_clk_en),        // the snoop baud generator's 1x tick
        .data_in (telem_byte(telem_idx)),
        .tx_en   (!telem_req),             // active low
        .tx      (GPIO_0[4]),
        .tx_busy (telem_tx_busy)
    );

    // ------------------------------------------------------------------------
    // Indicators
    // ------------------------------------------------------------------------
    // 3 verdict bits + 4 fault bits + alert + activity = 9, so they fit the ten
    // red LEDs with one to spare. error_status needs six bits and is easier to
    // read as hex, so it goes to the digits.
    assign LEDR[2:0] = status_leds;         // [2] Critical [1] Warning [0] Normal
    assign LEDR[6:3] = sensor_fault_mask;   // one per vibration channel
    assign LEDR[7]   = alert_flag;
    assign LEDR[8]   = (act_cnt != '0);     // blinks while bytes arrive
    assign LEDR[9]   = |error_status;       // any sticky fault at all

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

    assign HEX0 = hex7seg(error_status[3:0]);
    assign HEX1 = hex7seg({2'b00, error_status[5:4]});
    assign HEX2 = hex7seg(byte_count[3:0]);
    assign HEX3 = hex7seg(byte_count[7:4]);   // low byte only; B= in telemetry has all 16

endmodule
