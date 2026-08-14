module perceptron_tb_basic ();

  localparam int NUM_INPUTS = 2;
  localparam int DATA_WIDTH = 8;
  localparam int Q_FRAC     = 15;

  // unity gain in Q<Q_FRAC>: (sum * UNITY_SCALE) >>> Q_FRAC == sum
  localparam logic signed [23:0] UNITY_SCALE = 24'sd1 <<< Q_FRAC;

  localparam logic signed [DATA_WIDTH-1:0] AND_WEIGHTS  [NUM_INPUTS] = '{8'sd1,  8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] AND_BIAS  = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] OR_WEIGHTS   [NUM_INPUTS] = '{8'sd2,  8'sd2};
  localparam logic signed [DATA_WIDTH-1:0] OR_BIAS   = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NOT_WEIGHTS  [1]          = '{-8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NOT_BIAS  =  8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NOR_WEIGHTS  [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NOR_BIAS  =  8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NAND_WEIGHTS [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NAND_BIAS =  8'sd2;

  logic signed [DATA_WIDTH-1:0] inputs    [NUM_INPUTS];
  logic signed [DATA_WIDTH-1:0] not_input [1];

  // full-width results, thresholded below
  logic signed [DATA_WIDTH-1:0] and_out;
  logic signed [DATA_WIDTH-1:0] or_out;
  logic signed [DATA_WIDTH-1:0] not_out;
  logic signed [DATA_WIDTH-1:0] nor_out;
  logic signed [DATA_WIDTH-1:0] nand_out;

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(AND_WEIGHTS),
    .BIAS(AND_BIAS),
    .SCALE(UNITY_SCALE)
  ) and_perceptron (
    .inputs(inputs),
    .out(and_out)
  );

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(OR_WEIGHTS),
    .BIAS(OR_BIAS),
    .SCALE(UNITY_SCALE)
  ) or_perceptron (
    .inputs(inputs),
    .out(or_out)
  );

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(NAND_WEIGHTS),
    .BIAS(NAND_BIAS),
    .SCALE(UNITY_SCALE)
  ) nand_perceptron (
    .inputs(inputs),
    .out(nand_out)
  );

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(NOR_WEIGHTS),
    .BIAS(NOR_BIAS),
    .SCALE(UNITY_SCALE)
  ) nor_perceptron (
    .inputs(inputs),
    .out(nor_out)
  );

  perceptron #(
    .NUM_INPUTS(1),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(NOT_WEIGHTS),
    .BIAS(NOT_BIAS),
    .SCALE(UNITY_SCALE)
  ) not_perceptron (
    .inputs(not_input),
    .out(not_out)
  );

  int error_count = 0;
  logic exp_and, exp_or, exp_nand, exp_nor, exp_not;
  logic got_and, got_or, got_nand, got_nor, got_not;
  logic in0, in1;

  task automatic check(input string name, input logic got, input logic exp,
                       input logic signed [DATA_WIDTH-1:0] raw);
    assert (got === exp)
      else begin
        $error("[%s FAIL] inputs %b,%b | expected %b | got %b (raw acc = %0d)",
               name, in1, in0, exp, got, raw);
        error_count++;
      end
  endtask

  initial begin
    $display("=== perceptron_tb_basic : logic gates ===");
    $display(" IN1 IN0 | AND  OR NAND NOR | NOT");
    for (int i = 0; i < 4; i++) begin
      in0 = i[0];
      in1 = i[1];

      inputs[0]    = in0 ? 8'sd1 : 8'sd0;
      inputs[1]    = in1 ? 8'sd1 : 8'sd0;
      not_input[0] = in0 ? 8'sd1 : 8'sd0;

      // Golden reference outputs
      exp_and  =   in1 & in0;
      exp_or   =   in1 | in0;
      exp_nand = ~(in1 & in0);
      exp_nor  = ~(in1 | in0);
      exp_not  =  ~in0;

      #5;

      // a fired neuron is any non-zero activation, not just an odd one
      got_and  = (and_out  != 0);
      got_or   = (or_out   != 0);
      got_nand = (nand_out != 0);
      got_nor  = (nor_out  != 0);
      got_not  = (not_out  != 0);

      $display("  %0b   %0b  |  %0b   %0b   %0b   %0b  |  %0b",
               in1, in0, got_and, got_or, got_nand, got_nor, got_not);

      check("AND",  got_and,  exp_and,  and_out);
      check("OR",   got_or,   exp_or,   or_out);
      check("NAND", got_nand, exp_nand, nand_out);
      check("NOR",  got_nor,  exp_nor,  nor_out);
      check("NOT",  got_not,  exp_not,  not_out);
    end

    if (error_count == 0)
      $display("SUCCESS: all perceptron truth tables matched expected outputs!");
    else
      $display("FAILURE: %0d assertion errors encountered.", error_count);

    $finish;
  end

endmodule
