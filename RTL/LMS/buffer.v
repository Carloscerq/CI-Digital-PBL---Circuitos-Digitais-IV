module buffer #(
    parameter WIDTH = 24
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire signed [WIDTH-1:0] sample_in,
    input  wire                    sample_valid,
    output wire                    sample_ready,
    output wire                    block_ready,
    input  wire                    fft_begin,
    input  wire                    fft_rd_en,
    input  wire [5:0]              fft_rd_addr,
    output reg signed [WIDTH-1:0]  fft_data_out,
    output reg                     fft_data_valid,
    input  wire                    fft_done
);

    reg signed [WIDTH-1:0] mem0 [0:63];
    reg signed [WIDTH-1:0] mem1 [0:63];

    reg       write_bank;
    reg [5:0] write_addr;
    reg bank0_full;
    reg bank1_full;
    reg read_bank;
    reg read_active;

    assign sample_ready = (write_bank == 1'b0) ? (~bank0_full) : (~bank1_full);

    assign block_ready =
        (read_active == 1'b0) &&
        (((read_bank == 1'b0) && bank0_full) ||
         ((read_bank == 1'b1) && bank1_full));

    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            write_bank <= 1'b0;
            write_addr <= 6'd0;
            bank0_full <= 1'b0;
            bank1_full <= 1'b0;
            read_bank <= 1'b0;
            read_active <= 1'b0;
            fft_data_out <= {WIDTH{1'b0}};
            fft_data_valid <= 1'b0;
        end else begin
            fft_data_valid <= 1'b0;

            if (sample_valid && sample_ready) begin
                if (write_bank == 1'b0)
                    mem0[write_addr] <= sample_in;
                else
                    mem1[write_addr] <= sample_in;

                if (write_addr == 6'd63) begin
                    write_addr <= 6'd0;
                    if (write_bank == 1'b0) begin
                        bank0_full <= 1'b1;
                        write_bank <= 1'b1;
                    end else begin
                        bank1_full <= 1'b1;
                        write_bank <= 1'b0;
                    end
                end else begin
                    write_addr <= write_addr + 1'b1;
                end
            end

            if (fft_begin && block_ready)
                read_active <= 1'b1;

            if (fft_rd_en && read_active) begin
                if (read_bank == 1'b0)
                    fft_data_out <= mem0[fft_rd_addr];
                else
                    fft_data_out <= mem1[fft_rd_addr];
                fft_data_valid <= 1'b1;
            end

            if (fft_done && read_active) begin
                read_active <= 1'b0;
                if (read_bank == 1'b0) begin
                    bank0_full <= 1'b0;
                    read_bank <= 1'b1;
                end else begin
                    bank1_full <= 1'b0;
                    read_bank <= 1'b0;
                end
            end
        end
    end
endmodule
