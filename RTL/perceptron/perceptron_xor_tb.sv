module perceptron_xor_tb ();

  localparam int NUM_INPUTS = 2;
  localparam int DATA_WIDTH = 8;

  localparam logic signed [DATA_WIDTH-1:0] AND_WEIGHTS [NUM_INPUTS] = '{8'sd1,  8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] AND_BIAS = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] OR_WEIGHTS [NUM_INPUTS] = '{8'sd2,  8'sd2};
  localparam logic signed [DATA_WIDTH-1:0] OR_BIAS = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NAND_WEIGHTS [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NAND_BIAS = 8'sd2;
  logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS];

  logic or_output;
  logic nand_output;
  logic signed [DATA_WIDTH-1:0] layer1_outputs [NUM_INPUTS];
  logic xor_output;

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(OR_WEIGHTS),
    .BIAS(OR_BIAS)
  ) or_perceptron (
    .inputs(inputs),
    .out(or_output)
  );

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(NAND_WEIGHTS),
    .BIAS(NAND_BIAS)
  ) nand_perceptron (
    .inputs(inputs),
    .out(nand_output)
  );

  assign layer1_outputs[0] = or_output   ? 8'sd1 : 8'sd0;
  assign layer1_outputs[1] = nand_output ? 8'sd1 : 8'sd0;

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(AND_WEIGHTS),
    .BIAS(AND_BIAS)
  ) and_perceptron (
    .inputs(layer1_outputs),
    .out(xor_output)
  );

  int error_count = 0;

  initial begin
    logic in0, in1;
    logic exp_xor;

    $display("---------------------------------");
    $display(" IN1  IN0 | OR NAND | XOR (Expected)");
    $display("---------------------------------");

    for (int i = 0; i < 4; i++) begin
      in0 = i[0];
      in1 = i[1];

      inputs[0] = in0 ? 8'sd1 : 8'sd0;
      inputs[1] = in1 ? 8'sd1 : 8'sd0;

      exp_xor = in1 ^ in0;

      #5;

      $display("  %0d    %0d  |  %0b   %0b  |  %0b   (%0b)", 
               in1, in0, or_output, nand_output, xor_output, exp_xor);

      assert (xor_output === exp_xor)
        else begin
          $error("[XOR FAIL] Inputs: %b,%b | Expected: %b | Got: %b", in1, in0, exp_xor, xor_output);
          error_count++;
        end
    end

    if (error_count == 0) begin
      $display("SUCCESS: XOR Neural Network verified!");
    end else begin
      $display("FAILURE: %0d errors found.", error_count);
    end

    $finish;
  end

endmodule