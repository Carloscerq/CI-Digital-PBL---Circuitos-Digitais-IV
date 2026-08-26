// ============================================================================
// Spectrogram to CNN Adapter
// ============================================================================

module spectrogram_to_cnn_adapter #(
    parameter int DATA_WIDTH = 24
)(
    // Spectrogram Master
    input  logic m_axis_valid,
    output logic m_axis_ready,
    input  logic signed [DATA_WIDTH-1:0] m_axis_data,
    input  logic m_axis_last,
    
    // CNN Slave
    output logic s_axis_valid,
    input  logic s_axis_ready,
    output logic signed [DATA_WIDTH-1:0] s_axis_data [0:3],
    output logic s_axis_last
);
    assign s_axis_valid = m_axis_valid;
    assign m_axis_ready = s_axis_ready;
    assign s_axis_last  = m_axis_last;
    
    // Connect channel 0 to spectrogram data, tie others to 0
    assign s_axis_data[0] = m_axis_data;
    assign s_axis_data[1] = '0;
    assign s_axis_data[2] = '0;
    assign s_axis_data[3] = '0;
endmodule