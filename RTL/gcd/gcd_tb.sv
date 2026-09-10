module gcd_tb ();
  localparam SIZE = 32;
  localparam N_SMALL = 5;
  localparam N_FULL = 33;
  localparam RANDOM_TRIALS = 50;

  logic clk;
  logic reset;

  logic start_small;
  logic [SIZE-1: 0] in_small [N_SMALL];
  logic [SIZE-1: 0] out_small;
  logic ready_small;

  logic start_full;
  logic [SIZE-1: 0] in_full [N_FULL];
  logic [SIZE-1: 0] out_full;
  logic ready_full;

  gcd #(.AMOUNT_OF_NUMBERS(N_SMALL), .SIZE(SIZE)) dut_small (
    .clk(clk),
    .reset(reset),
    .start(start_small),
    .in(in_small),
    .out(out_small),
    .ready(ready_small)
  );

  gcd #(.AMOUNT_OF_NUMBERS(N_FULL), .SIZE(SIZE)) dut_full (
    .clk(clk),
    .reset(reset),
    .start(start_full),
    .in(in_full),
    .out(out_full),
    .ready(ready_full)
  );

  initial begin
    clk = 0;
    forever clk = #5 ~clk;
  end

  // keeps a broken handshake from hanging the simulation forever
  initial begin
    #50_000_000;
    $display("Error: timeout, the testbench never finished");
    $display("Finished testbench");
    $display("%d errors", amount_of_errors + 1);
    $finish;
  end

  integer amount_of_errors = 0;
  integer i;
  integer trial;
  integer factor;
  logic [SIZE-1: 0] expected;

  // behavioural reference, used to check the randomized trials
  function automatic [SIZE-1: 0] ref_gcd(
    input [SIZE-1: 0] a,
    input [SIZE-1: 0] b
  );
    logic [SIZE-1: 0] tmp;
    begin
      while (b != 0) begin
        tmp = b;
        b = a % b;
        a = tmp;
      end
      ref_gcd = a;
    end
  endfunction

  task load_small(
    input [SIZE-1: 0] a,
    input [SIZE-1: 0] b,
    input [SIZE-1: 0] c,
    input [SIZE-1: 0] d,
    input [SIZE-1: 0] e
  );
    begin
      in_small[0] = a;
      in_small[1] = b;
      in_small[2] = c;
      in_small[3] = d;
      in_small[4] = e;
    end
  endtask

  task validate_small(input [SIZE-1: 0] compare_value);
    begin
      @(negedge clk);
      start_small = 1;
      @(negedge clk) start_small = 0;
      @(posedge ready_small);
      #1;

      if (out_small != compare_value) begin
        $display("Error: got %d but should be %d - in: %d %d %d %d %d",
                 out_small, compare_value,
                 in_small[0], in_small[1], in_small[2], in_small[3], in_small[4]);
        amount_of_errors = amount_of_errors + 1;
      end
    end
  endtask

  task validate_full(input [SIZE-1: 0] compare_value);
    begin
      @(negedge clk);
      start_full = 1;
      @(negedge clk) start_full = 0;
      @(posedge ready_full);
      #1;

      if (out_full != compare_value) begin
        $display("Error: got %d but should be %d", out_full, compare_value);
        amount_of_errors = amount_of_errors + 1;
      end
    end
  endtask

  initial begin
    start_small = 0;
    start_full = 0;
    reset = 1'b0;
    load_small(0, 0, 0, 0, 0);
    for (i = 0; i < N_FULL; i = i + 1) in_full[i] = 0;

    @(negedge clk) reset = 1'b1;
    @(negedge clk) reset = 1'b0;

    // directed cases
    load_small(12, 18, 24, 36, 60);      validate_small(6);
    load_small(1071, 462, 21, 105, 84);  validate_small(21);
    load_small(9, 6, 3, 12, 15);         validate_small(3);
    load_small(8, 8, 8, 8, 4);           validate_small(4);
    // every number equal, the gcd is the number itself
    load_small(7, 7, 7, 7, 7);           validate_small(7);
    // coprimes, gcd is 1 (also exercises the early exit)
    load_small(13, 17, 19, 23, 29);      validate_small(1);
    // zeros are neutral, gcd(0, x) = x
    load_small(100, 0, 50, 0, 25);       validate_small(25);
    load_small(0, 0, 0, 0, 25);          validate_small(25);
    // all zeros, nothing to divide
    load_small(0, 0, 0, 0, 0);           validate_small(0);
    // the module must accept a new start right after finishing
    load_small(12, 18, 24, 36, 60);      validate_small(6);

    // randomized trials against the reference, on the full sized array
    for (trial = 0; trial < RANDOM_TRIALS; trial = trial + 1) begin
      // half of the trials get a planted common factor so the expected gcd
      // is not almost always 1
      factor = (trial % 2 == 0) ? (($random & 32'h0000_003F) + 1) : 1;

      // euclidian_gcd subtracts instead of dividing, so it takes O(a/b) cycles.
      // the operands are kept small on purpose to keep the simulation short
      expected = 0;
      for (i = 0; i < N_FULL; i = i + 1) begin
        in_full[i] = factor * ($random & 32'h0000_03FF);
        expected = ref_gcd(expected, in_full[i]);
      end

      validate_full(expected);
    end

    $display("Finished testbench");
    $display("%d errors", amount_of_errors);
    $finish;

  end

endmodule
