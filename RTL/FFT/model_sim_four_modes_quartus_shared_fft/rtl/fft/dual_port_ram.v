module dual_port_ram #(
    parameter DATA_WIDTH = 25,
    parameter ADDR_WIDTH = 6,
    parameter DEPTH      = 64,
    parameter INIT_FILE  = "NONE"
)(
    input  wire                  clk,

    input  wire                  we_a,
    input  wire [ADDR_WIDTH-1:0] addr_a,
    input  wire [DATA_WIDTH-1:0] data_in_a,
    output wire [DATA_WIDTH-1:0] data_out_a,

    input  wire                  we_b,
    input  wire [ADDR_WIDTH-1:0] addr_b,
    input  wire [DATA_WIDTH-1:0] data_in_b,
    output wire [DATA_WIDTH-1:0] data_out_b
);

`ifdef RTL_SIM

    
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];
    reg [DATA_WIDTH-1:0] data_out_a_reg;
    reg [DATA_WIDTH-1:0] data_out_b_reg;

    assign data_out_a = data_out_a_reg;
    assign data_out_b = data_out_b_reg;

    initial begin
        if (INIT_FILE != "NONE")
            $readmemh(INIT_FILE, ram);
    end

    always @(posedge clk) begin
        if (we_a)
            ram[addr_a] = data_in_a;
        data_out_a_reg <= ram[addr_a];
    end

    always @(posedge clk) begin
        if (we_b)
            ram[addr_b] = data_in_b;
        data_out_b_reg <= ram[addr_b];
    end

    always @(posedge clk) begin
        if (we_a && we_b && (addr_a == addr_b))
            $display("[AVISO][dual_port_ram] escrita simultanea no endereco %0d",
                     addr_a);
    end

`else

   
    wire [2:0] eccstatus_unused;

    altsyncram #(
        .address_aclr_b("NONE"),
        .address_reg_b("CLOCK0"),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_a("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .indata_aclr_b("NONE"),
        .indata_reg_b("CLOCK0"),
        .intended_device_family("Cyclone V"),
        .lpm_type("altsyncram"),
        .numwords_a(DEPTH),
        .numwords_b(DEPTH),
        .operation_mode("BIDIR_DUAL_PORT"),
        .outdata_aclr_a("NONE"),
        .outdata_aclr_b("NONE"),
        .outdata_reg_a("UNREGISTERED"),
        .outdata_reg_b("UNREGISTERED"),
        .power_up_uninitialized("TRUE"),
        .ram_block_type("M10K"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
        .read_during_write_mode_port_b("NEW_DATA_NO_NBE_READ"),
        .width_a(DATA_WIDTH),
        .width_b(DATA_WIDTH),
        .widthad_a(ADDR_WIDTH),
        .widthad_b(ADDR_WIDTH),
        .width_byteena_a(1),
        .width_byteena_b(1),
        .wrcontrol_aclr_b("NONE"),
        .wrcontrol_wraddress_reg_b("CLOCK0")
    ) ram_component (
        .aclr0(1'b0),
        .aclr1(1'b0),
        .address_a(addr_a),
        .address_b(addr_b),
        .addressstall_a(1'b0),
        .addressstall_b(1'b0),
        .byteena_a(1'b1),
        .byteena_b(1'b1),
        .clock0(clk),
        .clock1(1'b1),
        .clocken0(1'b1),
        .clocken1(1'b1),
        .clocken2(1'b1),
        .clocken3(1'b1),
        .data_a(data_in_a),
        .data_b(data_in_b),
        .eccstatus(eccstatus_unused),
        .q_a(data_out_a),
        .q_b(data_out_b),
        .rden_a(1'b1),
        .rden_b(1'b1),
        .wren_a(we_a),
        .wren_b(we_b)
    );

`endif

endmodule
