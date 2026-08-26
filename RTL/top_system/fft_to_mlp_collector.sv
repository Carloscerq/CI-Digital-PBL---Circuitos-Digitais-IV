// ============================================================================
// FFT to MLP Feature Collector
// ============================================================================
module fft_to_mlp_collector #(
    parameter int DATA_WIDTH = 24,
    parameter int N_IN = 132
)(
    input  logic clk,
    input  logic reset_n,
    
    // FFT Inputs
    input  logic fft_valid,
    input  logic [5:0] fft_bin,
    input  logic signed [DATA_WIDTH-1:0] fft_real,
    input  logic signed [DATA_WIDTH-1:0] fft_imag,
    input  logic fft_done,
    
    // External Features
    input  logic signed [DATA_WIDTH-1:0] ext_gcd,
    input  logic signed [DATA_WIDTH-1:0] ext_temperature,
    input  logic signed [DATA_WIDTH-1:0] ext_voltage,
    input  logic signed [DATA_WIDTH-1:0] ext_other,

    // MLP Interface
    output logic signed [DATA_WIDTH-1:0] mlp_features [N_IN],
    output logic mlp_start,
    input  logic mlp_busy
);
    logic signed [DATA_WIDTH-1:0] features_reg [N_IN];
    assign mlp_features = features_reg;
    
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            mlp_start <= 1'b0;
            for (int i = 0; i < N_IN; i++) begin
                features_reg[i] <= '0;
            end
        end else begin
            mlp_start <= 1'b0;
            
            if (fft_valid) begin
                // Map real to 0-63, imag to 64-127
                features_reg[fft_bin]      <= fft_real;
                features_reg[fft_bin + 64] <= fft_imag;
            end
            
            if (fft_done) begin
                features_reg[128] <= ext_gcd;
                features_reg[129] <= ext_temperature;
                features_reg[130] <= ext_voltage;
                features_reg[131] <= ext_other;
                if (!mlp_busy) begin
                    mlp_start <= 1'b1;
                end
            end
        end
    end
endmodule