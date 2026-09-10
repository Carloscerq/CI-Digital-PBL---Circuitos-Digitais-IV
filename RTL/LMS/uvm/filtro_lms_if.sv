// ---------------------------------------------------------------------
//  filtro_lms_if  --  connects the UVM agent to the filtro_lms DUT.
//
//  `clk` is the DUT's real clock, latched on posedge. `reset` is wired
//  straight through to the DUT's port of the same name: an ACTIVE-HIGH
//  synchronous reset (`always @(posedge clk) if (reset) ...`), the same
//  convention as every other block in this repo. All other signals are plain
//  (non-clocking-block) logic, driven/sampled directly by the
//  driver/monitor/top, mirroring tb_filtro_lms.v's own negedge-driven
//  style.
// ---------------------------------------------------------------------
interface filtro_lms_if (
    input logic clk
);

    logic reset;      // active-high synchronous reset

    logic in_valid;
    logic in_ready;

    logic signed [23:0] fft_re;
    logic signed [23:0] fft_im;

    logic signed [23:0] filt_re;
    logic signed [23:0] filt_im;

    logic out_valid;

endinterface
