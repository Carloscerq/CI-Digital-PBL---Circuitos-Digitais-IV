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
module spi_controller #(
  parameter int SIZE = 8,
  parameter int CLK_DIV = 4, // serial_clock = clk / (2*CLK_DIV)
  parameter int AMOUNT_OF_SLAVES = 2,
  parameter bit CPOL = 1'b0,
  parameter bit CPHA  = 1'b0,
  localparam int ADDR_W = (AMOUNT_OF_SLAVES > 1) ? $clog2(AMOUNT_OF_SLAVES) : 1
) (
  input logic clk,
  input logic reset_n,
  // fabric side
  input logic [SIZE-1:0] data_in,
  input logic [ADDR_W-1:0] address,
  input logic start,
  output logic ready,
  output logic [SIZE-1:0] data_out, // word received
  output logic data_valid,          // 1-cycle pulse: data_out is good
  // pins
  output logic serial_clock,
  output logic slave_in_controller_out,
  input logic controller_in_slave_out,
  output logic [AMOUNT_OF_SLAVES-1:0] slave_select_n // one-hot, active low
);

endmodule
