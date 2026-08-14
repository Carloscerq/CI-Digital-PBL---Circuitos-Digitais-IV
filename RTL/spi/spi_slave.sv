module spi_slave #(
  parameter int SIZE = 8,
  parameter bit CPOL = 1'b0,
  parameter bit CPHA = 1'b0
) (
  input logic clk,
  input logic reset_n,
  // fabric side
  input logic [SIZE-1:0] data_in,   // word to send on the next transfer
  output logic [SIZE-1:0] data_out, // word received
  output logic data_valid,          // 1-cycle pulse: data_out is good
  output logic busy,                // selected, a transfer is in progress
  // pins
  input logic serial_clock,
  input logic slave_in_controller_out,  // driven by the controller
  output logic controller_in_slave_out, // driven by this slave
  input logic slave_select_n
);

  localparam int COUNTER_SIZE = (SIZE > 1) ? $clog2(SIZE) : 1;

  // Two flop synchronisers. serial_clock and slave_select_n get a third stage
  // so their edges can be spotted without looking at the metastable flop.
  logic [2:0] sclk_sync;
  logic [2:0] select_sync;
  logic [1:0] mosi_sync;

  logic [SIZE-1:0]         tx_shift;
  logic [SIZE-1:0]         rx_shift;
  logic [COUNTER_SIZE-1:0] counter; // bits received so far
  logic                    miso;

  logic selected, sclk, sclk_prev, mosi;
  assign selected  = !select_sync[1];
  assign sclk      = sclk_sync[1];
  assign sclk_prev = sclk_sync[2];
  assign mosi      = mosi_sync[1];

  // The select just fell: a new transfer is starting.
  logic select_fell;
  assign select_fell = !select_sync[1] && select_sync[2];

  // A leading edge is the one that takes serial_clock away from its idle
  // level. CPHA picks which of the two samples the incoming bit; the other
  // one shifts the next bit out.
  logic clock_edge, leading_edge, sample_edge;
  assign clock_edge   = (sclk != sclk_prev);
  assign leading_edge = (sclk != CPOL);
  assign sample_edge  = (leading_edge != CPHA);

  assign busy = selected;
  // only the selected slave drives the shared line
  assign controller_in_slave_out = selected ? miso : 1'b0;

  always_ff @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
      sclk_sync   <= {3{CPOL}};
      select_sync <= '1;
      mosi_sync   <= '0;
      tx_shift    <= '0;
      rx_shift    <= '0;
      counter     <= '0;
      miso        <= 1'b0;
      data_out    <= '0;
      data_valid  <= 1'b0;
    end else begin
      sclk_sync   <= {sclk_sync[1:0], serial_clock};
      select_sync <= {select_sync[1:0], slave_select_n};
      mosi_sync   <= {mosi_sync[0], slave_in_controller_out};

      data_valid <= 1'b0;

      if (select_fell) begin
        // Mirrors the master's load: with CPHA = 0 the first bit has to be on
        // the wire before the first (sampling) edge, with CPHA = 1 the first
        // leading edge drives it.
        miso     <= CPHA ? miso : data_in[SIZE-1];
        tx_shift <= CPHA ? data_in : SIZE'(data_in << 1);
        rx_shift <= '0;
        counter  <= '0;
      end else if (selected && clock_edge) begin
        if (sample_edge) begin
          rx_shift <= SIZE'({rx_shift, mosi});

          if (counter == COUNTER_SIZE'(SIZE - 1)) begin
            data_out   <= SIZE'({rx_shift, mosi});
            data_valid <= 1'b1;
            counter    <= '0;
            // The master may keep the select down and send another word, so
            // take a fresh transmit word here. This lands one edge before the
            // next shift edge in both CPHA settings, which is where the whole
            // word still has to be present for its top bit to go out.
            tx_shift <= data_in;
          end else begin
            counter <= counter + 1'b1;
          end
        end else begin
          miso     <= tx_shift[SIZE-1];
          tx_shift <= SIZE'(tx_shift << 1);
        end
      end
    end
  end

endmodule
