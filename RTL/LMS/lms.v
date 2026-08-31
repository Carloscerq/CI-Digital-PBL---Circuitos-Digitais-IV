module lms #(
    parameter WIDTH = 24,
    parameter FRAC  = 15,
    parameter signed [WIDTH-1:0] MU_Q = 24'sd256
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire signed [WIDTH-1:0] sample_in,
    input  wire                    sample_valid,
    output wire                    sample_ready,
    output reg signed [WIDTH-1:0]  filtered_out,
    output reg signed [WIDTH-1:0]  error_out,
    output reg                     filtered_valid,
    input  wire                    filtered_ready
);

    reg signed [WIDTH-1:0] x0;
    reg signed [WIDTH-1:0] x1;
    reg signed [WIDTH-1:0] x2;
    reg signed [WIDTH-1:0] x3;

    reg signed [WIDTH-1:0] w0;
    reg signed [WIDTH-1:0] w1;
    reg signed [WIDTH-1:0] w2;
    reg signed [WIDTH-1:0] w3;

    wire signed [(2*WIDTH)-1:0] p0;
    wire signed [(2*WIDTH)-1:0] p1;
    wire signed [(2*WIDTH)-1:0] p2;
    wire signed [(2*WIDTH)-1:0] p3;

    wire signed [(2*WIDTH)+1:0] soma_produtos;
    wire signed [(2*WIDTH)+1:0] y_shift;
    wire signed [WIDTH-1:0] y_calc;
    wire signed [WIDTH-1:0] e_calc;

    wire signed [(2*WIDTH)-1:0] ex0;
    wire signed [(2*WIDTH)-1:0] ex1;
    wire signed [(2*WIDTH)-1:0] ex2;
    wire signed [(2*WIDTH)-1:0] ex3;

    wire signed [WIDTH-1:0] grad0;
    wire signed [WIDTH-1:0] grad1;
    wire signed [WIDTH-1:0] grad2;
    wire signed [WIDTH-1:0] grad3;

    wire signed [(2*WIDTH)-1:0] mug0;
    wire signed [(2*WIDTH)-1:0] mug1;
    wire signed [(2*WIDTH)-1:0] mug2;
    wire signed [(2*WIDTH)-1:0] mug3;

    wire signed [WIDTH-1:0] dw0;
    wire signed [WIDTH-1:0] dw1;
    wire signed [WIDTH-1:0] dw2;
    wire signed [WIDTH-1:0] dw3;

    assign sample_ready = (~filtered_valid) | filtered_ready;

    assign p0 = w0 * x0;
    assign p1 = w1 * x1;
    assign p2 = w2 * x2;
    assign p3 = w3 * x3;

    assign soma_produtos =
          {{2{p0[(2*WIDTH)-1]}}, p0}
        + {{2{p1[(2*WIDTH)-1]}}, p1}
        + {{2{p2[(2*WIDTH)-1]}}, p2}
        + {{2{p3[(2*WIDTH)-1]}}, p3};

    assign y_shift = soma_produtos >>> FRAC;
    assign y_calc = y_shift[WIDTH-1:0];
    assign e_calc = sample_in - y_calc;

    assign ex0 = e_calc * x0;
    assign ex1 = e_calc * x1;
    assign ex2 = e_calc * x2;
    assign ex3 = e_calc * x3;

    assign grad0 = ex0 >>> FRAC;
    assign grad1 = ex1 >>> FRAC;
    assign grad2 = ex2 >>> FRAC;
    assign grad3 = ex3 >>> FRAC;

    assign mug0 = grad0 * MU_Q;
    assign mug1 = grad1 * MU_Q;
    assign mug2 = grad2 * MU_Q;
    assign mug3 = grad3 * MU_Q;

    assign dw0 = mug0 >>> FRAC;
    assign dw1 = mug1 >>> FRAC;
    assign dw2 = mug2 >>> FRAC;
    assign dw3 = mug3 >>> FRAC;

    always @(posedge clk) begin
        if (reset) begin
            x0 <= {WIDTH{1'b0}};
            x1 <= {WIDTH{1'b0}};
            x2 <= {WIDTH{1'b0}};
            x3 <= {WIDTH{1'b0}};
            w0 <= {WIDTH{1'b0}};
            w1 <= {WIDTH{1'b0}};
            w2 <= {WIDTH{1'b0}};
            w3 <= {WIDTH{1'b0}};
            filtered_out   <= {WIDTH{1'b0}};
            error_out      <= {WIDTH{1'b0}};
            filtered_valid <= 1'b0;
        end else begin
            if (filtered_valid && filtered_ready)
                filtered_valid <= 1'b0;

            if (sample_valid && sample_ready) begin
                filtered_out <= y_calc;
                error_out <= e_calc;
                filtered_valid <= 1'b1;
                w0 <= w0 + dw0;
                w1 <= w1 + dw1;
                w2 <= w2 + dw2;
                w3 <= w3 + dw3;
                x3 <= x2;
                x2 <= x1;
                x1 <= x0;
                x0 <= sample_in;
            end
        end
    end
endmodule
