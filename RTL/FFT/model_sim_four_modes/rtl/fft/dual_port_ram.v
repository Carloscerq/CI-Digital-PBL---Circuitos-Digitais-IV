module dual_port_ram #(
    parameter DATA_WIDTH = 25,
    parameter ADDR_WIDTH = 6,
    parameter DEPTH      = 64,
    parameter INIT_FILE  = "NONE"
)(
    input  wire                  clk,
    input  wire                  reset,

    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] data_in_a,
    output reg  [DATA_WIDTH-1:0] data_out_a,

    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] data_in_b,
    output reg  [DATA_WIDTH-1:0] data_out_b
);

    (* ramstyle = "M10K" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    initial begin
        data_out_a = {DATA_WIDTH{1'b0}};
        data_out_b = {DATA_WIDTH{1'b0}};

        if (INIT_FILE != "NONE")
            $readmemh(INIT_FILE, ram);
    end

    // Porta A: leitura sincrona, comportamento read-during-write do tipo
    // "old data" na simulacao RTL devido as atribuicoes nao bloqueantes.
    always @(posedge clk) begin
        if (reset) begin
            data_out_a <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we_a)
                ram[addr_a] <= data_in_a;

            data_out_a <= ram[addr_a];
        end
    end

    // Porta B
    always @(posedge clk) begin
        if (reset) begin
            data_out_b <= {DATA_WIDTH{1'b0}};
        end else begin
            if (we_b)
                ram[addr_b] <= data_in_b;

            data_out_b <= ram[addr_b];
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && we_a && we_b && (addr_a == addr_b))
            $display("[AVISO][dual_port_ram] escrita simultanea no endereco %0d", addr_a);
    end
`endif

endmodule
