module euclidian_gcd_tb ();

  localparam SIZE = 8;

  logic clk;
  logic reset_n;
  logic start;
  logic [SIZE-1: 0] in_a;
  logic [SIZE-1: 0] in_b;
  logic [SIZE-1: 0] out;
  logic ready;

  euclidian_gcd #(.SIZE(SIZE)) dut (
    .clk(clk),
    .reset_n(reset_n),
    .start(start),
    .in_a(in_a),
    .in_b(in_b),
    .out(out),
    .ready(ready)
  );

  initial begin
    clk = 0;
    forever clk = #5 ~clk;
  end

  integer amount_of_errors = 0;
  task validate(
    input [SIZE-1: 0] dut_value,
    input [SIZE-1: 0] compare_value
  );
    begin
      if (dut_value != compare_value) begin
        $display("Error: got %d but should be %d", dut_value, compare_value);
        amount_of_errors = amount_of_errors + 1;
      end
    end
  endtask

  initial begin
    start = 0;
    in_a = 0;
    in_b = 0;
    reset_n = 1;

    @(negedge clk) reset_n = 0;
    @(negedge clk) reset_n = 1;

    
  end

endmodule