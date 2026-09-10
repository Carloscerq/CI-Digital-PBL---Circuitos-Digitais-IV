// ---------------------------------------------------------------------
//  spi_if  --  connects the UVM agent to the spi_controller +
//              spi_slave DUT pair.
//
//  `clk` is the shared system clock the whole bus runs on (both DUTs
//  are synchronous to it; spi_slave additionally double/triple-flop-
//  synchronises the serial pins onto it). `reset` is the shared system
//  reset, declared here as an ordinary interface variable rather than
//  an input port so that spi_driver can drive it from its UVM
//  reset_phase -- spi_uvm_top wires both DUTs' reset ports to
//  vif.reset.
//
//  Controller fabric side and pins are plain scalars/vectors, one each,
//  since there is exactly one controller. The slave side is per-slave:
//  N_SLAVES independent spi_slave instances share the serial pins
//  (serial_clock, mosi) but each gets its own fabric bus and its own
//  slave_select_n bit, so those are modelled as unpacked arrays sized
//  N_SLAVES, mirroring spi_controller_tb.sv's slave_data_in/
//  slave_data_out/slave_valid/slave_busy arrays.
// ---------------------------------------------------------------------
interface spi_if #(
    int SIZE     = 8,
    int N_SLAVES = 2
) (
    input logic clk
);

    localparam int ADDR_W = (N_SLAVES > 1) ? $clog2(N_SLAVES) : 1;

    // shared system reset, driven by spi_driver's reset_phase
    logic reset;

    // controller fabric side
    logic [SIZE-1:0]  data_in;
    logic [ADDR_W-1:0] address;
    logic              start;
    logic              hold_select;
    logic              ready;
    logic [SIZE-1:0]   data_out;
    logic              data_valid;

    // shared serial pins
    logic                serial_clock;
    logic                mosi;  // slave_in_controller_out
    logic                miso;  // controller_in_slave_out (bus mux, driven by top)
    logic [N_SLAVES-1:0] slave_select_n; // one-hot, active low

    // per-slave fabric side
    logic [SIZE-1:0] slave_data_in    [N_SLAVES];
    logic [SIZE-1:0] slave_data_out   [N_SLAVES];
    logic             slave_data_valid [N_SLAVES];
    logic             slave_busy       [N_SLAVES];

endinterface
