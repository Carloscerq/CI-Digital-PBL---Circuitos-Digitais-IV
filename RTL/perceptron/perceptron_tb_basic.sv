module perceptron_tb_basic ();
  
  localparam int NUM_INPUTS = 2;
  localparam int DATA_WIDTH = 8;

  localparam logic signed [DATA_WIDTH-1:0] AND_WEIGHTS [NUM_INPUTS] = '{8'sd1,  8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] AND_BIAS = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] OR_WEIGHTS [NUM_INPUTS] = '{8'sd2,  8'sd2};
  localparam logic signed [DATA_WIDTH-1:0] OR_BIAS = -8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NOT_WEIGHTS [1] = '{-8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NOT_BIAS = 8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NOR_WEIGHTS [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NOR_BIAS = 8'sd1;
  localparam logic signed [DATA_WIDTH-1:0] NAND_WEIGHTS [NUM_INPUTS] = '{-8'sd1, -8'sd1};
  localparam logic signed [DATA_WIDTH-1:0] NAND_BIAS = 8'sd2;

  logic signed [DATA_WIDTH-1:0] inputs [NUM_INPUTS];
  logic signed [DATA_WIDTH-1:0] not_input [1];

  logic and_output;
  logic or_output;
  logic not_output;
  logic nor_output;
  logic nand_output;

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(AND_WEIGHTS),
    .BIAS(AND_BIAS)
  ) and_perceptron (
    .inputs(inputs),
    .out(and_output)
  );

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

  perceptron #(
    .NUM_INPUTS(NUM_INPUTS),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(NOR_WEIGHTS),
    .BIAS(NOR_BIAS)
  ) nor_perceptron (
    .inputs(inputs),
    .out(nor_output)
  );

  perceptron #(
    .NUM_INPUTS(1),
    .DATA_WIDTH(DATA_WIDTH),
    .WEIGHTS(NOT_WEIGHTS),
    .BIAS(NOT_BIAS)
  ) not_perceptron (
    .inputs(not_input),
    .out(not_output)
  );

  int error_count = 0;
  logic exp_and;
  logic exp_or;
  logic exp_nand;
  logic exp_nor;
  logic exp_not;
  logic in0;
  logic in1;

  initial begin
    $display("Starting Perceptron Testbench...");
    for (int i = 0; i < 4; i++) begin
      in0 = i[0];
      in1 = i[1];

      inputs[0]    = in0 ? 8'sd1 : 8'sd0;
      inputs[1]    = in1 ? 8'sd1 : 8'sd0;
      not_input[0] = in0 ? 8'sd1 : 8'sd0;

      // Golden Reference Outputs
      exp_and  = in1 & in0;
      exp_or   = in1 | in0;
      exp_nand = ~(in1 & in0);
      exp_nor  = ~(in1 | in0);
      exp_not  = ~in0;

      #5;

      assert (and_output === exp_and) 
        else begin 
          $error("[AND FAIL] Inputs: %b,%b | Expected: %b | Got: %b", in1, in0, exp_and, and_output); 
          error_count++; 
        end

      assert (or_output === exp_or) 
        else begin 
          $error("[OR FAIL] Inputs: %b,%b | Expected: %b | Got: %b", in1, in0, exp_or, or_output); 
          error_count++; 
        end

      assert (nand_output === exp_nand) 
        else begin 
          $error("[NAND FAIL] Inputs: %b,%b | Expected: %b | Got: %b", in1, in0, exp_nand, nand_output); 
          error_count++; 
        end

      assert (nor_output === exp_nor) 
        else begin 
          $error("[NOR FAIL] Inputs: %b,%b | Expected: %b | Got: %b", in1, in0, exp_nor, nor_output); 
          error_count++; 
        end

      assert (not_output === exp_not) 
        else begin 
          $error("[NOT FAIL] Input: %b | Expected: %b | Got: %b", in0, exp_not, not_output); 
          error_count++; 
        end
    end

    if (error_count == 0) begin
      $display("SUCCESS: All perceptron truth tables matched expected outputs!");
    end else begin
      $display("FAILURE: %0d assertion errors encountered.", error_count);
    end

    $finish;
  end

endmodule