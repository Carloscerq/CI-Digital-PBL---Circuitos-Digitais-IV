`timescale 1ns / 1ps

// ============================================================================
// SPI Sensor Frame Receiver
// ============================================================================
// One chip-select assertion carries one complete sensor frame. The master
// sends N_SENSORS words back to back, each BYTES_PER_WORD bytes, MSB byte
// first:
//
//   word 0 .. 3 : vibration   0..3   -> shared FFT (one per FFT channel)
//   word 4 .. 6 : current     0..2   -> MLP extra features
//   word 7 .. 8 : temperature 0..1   -> MLP extra features
//
// so a frame is N_SENSORS * BYTES_PER_WORD = 27 bytes. `frame_valid` pulses
// for one cycle once the last byte has landed, with `sensor_data` holding the
// whole frame; it then stays stable until the next complete frame.
//
// The word/byte counters are re-zeroed on every chip-select release, so a
// truncated or overlong frame costs that one frame instead of permanently
// misaligning the channel mapping. Either case raises `frame_error`.
// ============================================================================
module spi_sensor_frame_rx #(
    parameter int DATA_WIDTH     = 24,
    parameter int N_SENSORS      = 9,
    parameter int BYTES_PER_WORD = 3
)(
    input  logic clk,
    input  logic reset_n,

    // spi_slave fabric side
    input  logic [7:0] spi_data,
    input  logic       spi_valid,
    input  logic       spi_selected,   // spi_slave.busy: high while CS is low

    // Registered snapshot of one complete frame
    output logic signed [DATA_WIDTH-1:0] sensor_data [0:N_SENSORS-1],
    output logic                         frame_valid,
    output logic                         frame_error
);

    localparam int WORD_IDX_W = (N_SENSORS      > 1) ? $clog2(N_SENSORS)      : 1;
    localparam int BYTE_IDX_W = (BYTES_PER_WORD > 1) ? $clog2(BYTES_PER_WORD) : 1;

    logic [WORD_IDX_W-1:0] word_idx;
    logic [BYTE_IDX_W-1:0] byte_idx;
    logic [DATA_WIDTH-1:0] shift_reg;

    // Words 0..N_SENSORS-2 are staged here; the final word is forwarded
    // straight from `word_now`, which is why the copy below stops one short.
    logic signed [DATA_WIDTH-1:0] capture [0:N_SENSORS-1];

    // The byte currently on `spi_data` completes the word being shifted in.
    logic signed [DATA_WIDTH-1:0] word_now;
    assign word_now = signed'({shift_reg[DATA_WIDTH-9:0], spi_data});

    logic word_complete;
    logic frame_complete;
    assign word_complete  = spi_valid &&
                            (byte_idx == BYTE_IDX_W'(BYTES_PER_WORD - 1));
    assign frame_complete = word_complete &&
                            (word_idx == WORD_IDX_W'(N_SENSORS - 1));

    // Chip select just went away: end of frame, wherever the counters are.
    logic selected_q;
    logic frame_end;
    assign frame_end = selected_q && !spi_selected;

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            word_idx    <= '0;
            byte_idx    <= '0;
            shift_reg   <= '0;
            selected_q  <= 1'b0;
            frame_valid <= 1'b0;
            frame_error <= 1'b0;
            for (int i = 0; i < N_SENSORS; i++) begin
                capture[i]     <= '0;
                sensor_data[i] <= '0;
            end
        end else begin
            frame_valid <= 1'b0;
            selected_q  <= spi_selected;

            if (spi_valid) begin
                shift_reg <= {shift_reg[DATA_WIDTH-9:0], spi_data};

                if (word_complete) begin
                    byte_idx   <= '0;
                    capture[word_idx] <= word_now;
                    word_idx   <= frame_complete ? '0 : (word_idx + 1'b1);
                end else begin
                    byte_idx <= byte_idx + 1'b1;
                end
            end

            if (frame_complete) begin
                for (int i = 0; i < N_SENSORS - 1; i++)
                    sensor_data[i] <= capture[i];
                sensor_data[N_SENSORS-1] <= word_now;
                frame_valid <= 1'b1;
            end

            // Resync. Landing here with non-zero counters means the master
            // released CS in the middle of a word or of the frame.
            if (frame_end) begin
                word_idx <= '0;
                byte_idx <= '0;
                // `frame_complete` may land on the same cycle if the master
                // drops CS immediately after the last byte; the counters read
                // here are still the pre-wrap ones, so exempt that case.
                if (!frame_complete && ((word_idx != '0) || (byte_idx != '0)))
                    frame_error <= 1'b1;
            end
        end
    end

    // synthesis translate_off
    initial begin
        if (DATA_WIDTH != 8 * BYTES_PER_WORD)
            $fatal(1, "[spi_sensor_frame_rx] DATA_WIDTH deve ser 8*BYTES_PER_WORD.");
    end
    // synthesis translate_on

endmodule
