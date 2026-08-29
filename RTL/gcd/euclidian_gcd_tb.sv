module euclidian_gcd_tb ();

  localparam SIZE = 64;

  logic clk;
  logic reset;
  logic start;
  logic [SIZE-1: 0] in_a;
  logic [SIZE-1: 0] in_b;
  logic [SIZE-1: 0] out;
  logic ready;

  euclidian_gcd #(.SIZE(SIZE)) dut (
    .clk(clk),
    .reset(reset),
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
    input [SIZE-1: 0] compare_value,
    input [SIZE-1: 0] a,
    input [SIZE-1: 0] b
  );
    begin
      @(negedge clk);
      in_a = a;
      in_b = b;
      start = 1;
      @(negedge clk) start = 0;
      @(posedge ready);

      if (out != compare_value) begin
        $display("Error: got %d but should be %d", out, compare_value);
        amount_of_errors = amount_of_errors + 1;
      end
    end
  endtask

  initial begin
    start = 0;
    in_a = 0;
    in_b = 0;
    reset = 1'b0;

    $monitor("[%t] - in_a: %d in_b: %d - start: %d - ready: %d", $time, in_a, in_b, start, ready);

    @(negedge clk) reset = 1'b1;
    @(negedge clk) reset = 1'b0;

    validate(5, 10, 5);
    validate(21, 1071, 462);
    validate(21, 462, 1071);
    validate(5, 5, 10);

    $display("Finished testbench");
    $display("%d errors", amount_of_errors);
    $finish;
    
  end

endmodule
