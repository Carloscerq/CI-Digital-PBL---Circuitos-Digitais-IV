// SPI controller (master).
//
// Generates serial_clock and the active-low chip selects; shifts SIZE bits out
// on slave_in_controller_out while simultaneously shifting SIZE bits in on
// controller_in_slave_out (SPI is full duplex).
//
// Mode is set by CPOL/CPHA:
//   CPOL = idle level of serial_clock (0 = idle low, 1 = idle high)
//   CPHA = 0 -> sample on leading edge, change on trailing edge
//          1 -> change on leading edge, sample on trailing edge
//
module spi_controller #(
  parameter int SIZE = 8,
  parameter int AMOUNT_OF_SLAVES = 2,
  parameter int CLK_DIV [AMOUNT_OF_SLAVES] = '{default: 4}, // clk/(2*CLK_DIV)
  parameter bit CPOL    [AMOUNT_OF_SLAVES] = '{default: 1'b0},
  parameter bit CPHA    [AMOUNT_OF_SLAVES] = '{default: 1'b0},
  // derived from AMOUNT_OF_SLAVES, not meant to be overridden.
  parameter int ADDR_W = (AMOUNT_OF_SLAVES > 1) ? $clog2(AMOUNT_OF_SLAVES) : 1
) (
  input logic clk,
  input logic reset,
  // fabric side
  input logic [SIZE-1:0] data_in,
  input logic [ADDR_W-1:0] address,
  input logic start,
  input logic hold_select, // keep the select down for a following word
  output logic ready,
  output logic [SIZE-1:0] data_out, // word received
  output logic data_valid,          // 1-cycle pulse: data_out is good
  // pins
  output logic serial_clock,
  output logic slave_in_controller_out,
  input logic controller_in_slave_out,
  output logic [AMOUNT_OF_SLAVES-1:0] slave_select_n // one-hot, active low
);

  localparam int TOTAL_EDGES = 2 * SIZE;
  localparam int COUNTER_SIZE = $clog2(TOTAL_EDGES);

  // The half period counter has to fit the slowest slave.
  function automatic int largest(input int values [AMOUNT_OF_SLAVES]);
    int result;
    result = values[0];
    for (int i = 1; i < AMOUNT_OF_SLAVES; i++)
      if (values[i] > result) result = values[i];
    return result;
  endfunction

  localparam int MAX_CLK_DIV = largest(CLK_DIV);
  localparam int DIV_W = (MAX_CLK_DIV > 1) ? $clog2(MAX_CLK_DIV) : 1;

  typedef enum logic [1:0] {
    S_IDLE,  // parked, serial_clock at its idle level, nothing selected
    S_LEAD,  // slave selected, half period of setup before the first edge
    S_XFER,  // toggling serial_clock, shifting data in and out
    S_TRAIL  // half period of hold before releasing the slave select
  } state_t;

  state_t state, next_state;

  logic [DIV_W-1:0] div_counter; // counts down one half period
  logic [COUNTER_SIZE-1:0] counter;     // which serial_clock edge we are on
  logic [SIZE-1:0] tx_shift;
  logic [SIZE-1:0] rx_shift;
  logic mosi;
  logic holding; // this word is part of a longer transaction

  // Mode and half period of the slave this transfer is talking to, taken from
  // the parameter arrays when the transfer is latched.
  logic             cpha_q;
  logic [DIV_W-1:0] div_reload;

  // Control strobes driven by the next-state logic.
  logic load;    // latch the request and select the slave
  logic advance; // flip serial_clock and shift a bit in/out
  logic finish;  // release the slave and publish the received word

  // The half period elapsed: this clk edge is the one that flips serial_clock.
  logic tick;
  assign tick = (div_counter == '0);

  logic last_edge;
  assign last_edge = (counter == COUNTER_SIZE'(TOTAL_EDGES - 1));

  // Even edges are the leading ones, odd edges the trailing ones. CPHA picks
  // which of the two samples the incoming bit; the other one shifts data out.
  logic sample_edge;
  assign sample_edge = (counter[0] == cpha_q);

  // Settings for the word about to be latched. While a transaction is held
  // open address is ignored, so the mode and the rate stay those of the slave
  // that opened it rather than following a stray address change.
  logic             eff_cpha;
  logic [DIV_W-1:0] eff_div;
  assign eff_cpha = holding ? cpha_q     : CPHA[address];
  assign eff_div  = holding ? div_reload : DIV_W'(CLK_DIV[address] - 1);

  assign ready = (state == S_IDLE);
  assign slave_in_controller_out = mosi;

  always_comb begin
    next_state = state;
    load = 1'b0;
    advance = 1'b0;
    finish = 1'b0;

    case (state)
      S_IDLE: begin
        if (start) begin
          load = 1'b1;
          next_state = S_LEAD;
        end
      end

      S_LEAD: begin
        if (tick) next_state = S_XFER;
      end

      S_XFER: begin
        if (tick) begin
          advance = 1'b1;
          if (last_edge) next_state = S_TRAIL;
        end
      end

      S_TRAIL: begin
        if (tick) begin
          finish = 1'b1;
          next_state = S_IDLE;
        end
      end

      default: next_state = S_IDLE;
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      state <= S_IDLE;
      div_counter <= '0;
      counter <= '0;
      tx_shift <= '0;
      rx_shift <= '0;
      mosi <= 1'b0;
      holding <= 1'b0;
      cpha_q <= CPHA[0];
      div_reload <= DIV_W'(CLK_DIV[0] - 1);
      serial_clock <= CPOL[0];
      slave_select_n <= '1;
      data_out <= '0;
      data_valid <= 1'b0;
    end else begin
      state <= next_state;
      data_valid <= finish;

      // half period timer: reloaded on every serial_clock half period
      if (load) div_counter <= eff_div;
      else if (tick) div_counter <= div_reload;
      else if (state != S_IDLE) div_counter <= div_counter - 1'b1;

      if (load) begin
        // With CPHA = 0 the first bit has to be on the wire before the first
        // (sampling) edge, so it is put there together with the chip select;
        // with CPHA = 1 the first leading edge drives it.
        mosi     <= eff_cpha ? mosi : data_in[SIZE-1];
        tx_shift <= eff_cpha ? data_in : SIZE'(data_in << 1);
        rx_shift <= '0;
        counter  <= '0;

        cpha_q     <= eff_cpha;
        div_reload <= eff_div;

        // Only the word that opens a transaction picks the slave and its idle
        // clock level. While one is being held open the select stays exactly
        // as it is, so changing address halfway cannot move it.
        if (!holding) begin
          slave_select_n <= ~(AMOUNT_OF_SLAVES'(1) << address);
          serial_clock   <= CPOL[address];
        end
        holding <= hold_select;
      end

      if (advance) begin
        serial_clock <= ~serial_clock;
        counter      <= counter + 1'b1;

        if (sample_edge) begin
          // The slave keeps the bit stable across this edge, so the value
          // seen here is the one it is presenting.
          rx_shift <= SIZE'({rx_shift, controller_in_slave_out});
        end else begin
          mosi     <= tx_shift[SIZE-1];
          tx_shift <= SIZE'(tx_shift << 1);
        end
      end

      if (finish) begin
        // holding still carries what this word asked for, so the select only
        // goes back up on the word that closes the transaction
        if (!holding) slave_select_n <= '1;
        data_out <= rx_shift;
      end
    end
  end

endmodule
