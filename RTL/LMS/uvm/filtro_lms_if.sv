// ---------------------------------------------------------------------
//  filtro_lms_if  --  connects the UVM agent to the filtro_lms DUT.
//
//  `clk` is the DUT's real clock, latched on posedge. `reset` is wired
//  straight through to the DUT's port of the same name -- despite that
//  name it is an ACTIVE-LOW asynchronous reset (`always @(posedge clk or
//  negedge reset) if (!reset) ...`, same convention as mac.sv's `rst_n`,
//  just misleadingly named in this module). All other signals are plain
//  (non-clocking-block) logic, driven/sampled directly by the
//  driver/monitor/top, mirroring tb_filtro_lms.v's own negedge-driven
//  style.
// ---------------------------------------------------------------------
interface filtro_lms_if (
    input logic clk
);

    logic reset;      // active-low async reset (see note above)

    logic in_valid;
    logic in_ready;

    logic signed [23:0] fft_re;
    logic signed [23:0] fft_im;

    logic signed [23:0] filt_re;
    logic signed [23:0] filt_im;

    logic out_valid;

endinterface
