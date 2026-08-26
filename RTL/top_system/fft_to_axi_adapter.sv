// ============================================================================
// FFT to AXI4-Stream Adapter for Spectrogram
// ============================================================================

module fft_to_axi_adapter #(
    parameter int DATA_WIDTH = 24
)(
    input  logic clk,
    input  logic rst,
    
    // FFT side
    input  logic fft_valid,
    input  logic [5:0] fft_bin,
    input  logic signed [DATA_WIDTH-1:0] fft_real,
    
    // AXI4-Stream side
    output logic s_axis_valid,
    input  logic s_axis_ready,
    output logic signed [DATA_WIDTH-1:0] s_axis_data,
    output logic s_axis_last
);
    // Forward only the first 32 bins to match Spectrogram's BINS_PER_FRAME (32)
    assign s_axis_valid = fft_valid && (fft_bin < 6'd32);
    assign s_axis_data  = fft_real;
    assign s_axis_last  = fft_valid && (fft_bin == 6'd31);
endmodule