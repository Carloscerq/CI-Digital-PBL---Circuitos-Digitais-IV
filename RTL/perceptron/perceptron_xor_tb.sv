module perceptron_xor_tb ();

  localparam int NUM_INPUTS = 2;
  localparam int DATA_WIDTH = 8;
  localparam int Q_FRAC     = 15;

  localparam logic signed [23:0] UNITY_SCALE = 24'sd1 <<< Q_FRAC;

  localparam logic signed [DATA_WIDTH-1:0] AND_WEIGHTS  [NUM_INPUTS] = '{8'sd1,  8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] AND_BIAS  = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] OR_WEIGHTS   [NUM_INPUTS] = '{8'sd2,  8'sd2};
  localparam logic signed [DATA_WIDTH-1:0] OR_BIAS   = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NAND_WEIGHTS [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NAND_BIAS =  8'sd2;

  logic signed [DATA_WIDTH-1:0] inputs         [NUM_INPUTS];
  logic signed [DATA_WIDTH-1:0] layer1_outputs [NUM_INPUTS];

  logic signed [DATA_WIDTH-1:0] or_out;
  logic signed [DATA_WIDTH-1:0] nand_out;
  logic signed [DATA_WIDTH-1:0] xor_out;

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

  // re-quantise: fired (non-zero) -> 1, silent -> 0
  assign layer1_outputs[0] = (or_out   != 0) ? 8'sd1 : 8'sd0;
  assign layer1_outputs[1] = (nand_out != 0) ? 8'sd1 : 8'sd0;

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .Q_FRAC(Q_FRAC),
    .RELU(1),
    .WEIGHTS(AND_WEIGHTS),
    .BIAS(AND_BIAS),
    .SCALE(UNITY_SCALE)
  ) and_perceptron (
    .inputs(layer1_outputs),
    .out(xor_out)
  );

  int error_count = 0;

  initial begin
    logic in0, in1;
    logic exp_xor, got_xor;

    $display("=== perceptron_xor_tb : XOR = AND(OR, NAND) ===");
    $display(" IN1 IN0 |  OR NAND | XOR (expected)");

    for (int i = 0; i < 4; i++) begin
      in0 = i[0];
      in1 = i[1];

      inputs[0] = in0 ? 8'sd1 : 8'sd0;
      inputs[1] = in1 ? 8'sd1 : 8'sd0;

      exp_xor = in1 ^ in0;

      #5;

      got_xor = (xor_out != 0);

      $display("  %0b   %0b  |   %0b    %0b  |  %0b   (%0b)",
               in1, in0, (or_out != 0), (nand_out != 0), got_xor, exp_xor);

      assert (got_xor === exp_xor)
        else begin
          $error("[XOR FAIL] inputs %b,%b | expected %b | got %b (raw acc = %0d)",
                 in1, in0, exp_xor, got_xor, xor_out);
          error_count++;
        end
    end

    if (error_count == 0)
      $display("SUCCESS: XOR neural network verified!");
    else
      $display("FAILURE: %0d errors found.", error_count);

    $finish;
  end

endmodule
