// ---------------------------------------------------------------------
//  perceptron_tb_fixedpoint  --  covers what the gate benches cannot
//
//    1. unity scale                 : (sum * 1<<Q_FRAC) >>> Q_FRAC == sum
//    2. fractional scale            : arithmetic >>> floors negatives
//    3. bias sign extension         : PROD_WIDTH'(BIAS) must sign-extend
//    4. saturation high / low       : result clips, never wraps
//    5. RELU parameter              : 1 clamps negatives, 0 passes them
//    6. wide-product regression     : 40 x 24-bit inputs at SCALE = 883,
//                                     the layer-0 configuration. With the
//                                     old ACCUM_WIDTH-wide product this
//                                     case wrapped to -2999215 (-> ReLU 0)
//                                     instead of 5389393.
//    7. randomised layer-0 sweep against a 64-bit golden model
// ---------------------------------------------------------------------
module perceptron_tb_fixedpoint ();

  int error_count = 0;

  // ---- 64-bit golden model, independent of the DUT's internal widths ----
  function automatic longint signed golden(input longint signed sum,
                                          input longint signed scale,
                                          input longint signed bias,
                                          input int q,
                                          input bit relu,
                                          input int dw);
    longint signed acc, hi, lo;
    acc = ((sum * scale) >>> q) + bias;
    hi  =  (64'sd1 <<< (dw - 1)) - 1;
    lo  = -(64'sd1 <<< (dw - 1));
    if (relu && acc < 0) return 0;
    else if (acc > hi)   return hi;
    else if (acc < lo)   return lo;
    else                 return acc;
  endfunction

  task automatic check(input string name,
                       input longint signed got,
                       input longint signed exp);
    if (got !== exp) begin
      $error("[%s FAIL] expected %0d | got %0d", name, exp, got);
      error_count++;
    end else begin
      $display("  ok  %-22s = %0d", name, got);
    end
  endtask

  // =====================================================================
  //  1. unity scale, ReLU on:  out = ReLU(in0 - in1)
  // =====================================================================
  localparam logic signed [7:0] W_DIFF [2] = '{8'sd1, -8'sd1};
  logic signed [7:0] in_unity [2];
  logic signed [7:0] out_unity;

  perceptron #(
    .NUM_INPUTS(2), .DATA_WIDTH(8), .Q_FRAC(15), .RELU(1),
    .WEIGHTS(W_DIFF), .BIAS(8'sd0), .SCALE(24'sd1 <<< 15)
  ) dut_unity (.inputs(in_unity), .out(out_unity));

  // =====================================================================
  //  2. scale = 0.5, ReLU off: negative results must FLOOR, not truncate
  // =====================================================================
  localparam logic signed [7:0] W_NEG1 [1] = '{-8'sd1};
  logic signed [7:0] in_frac [1];
  logic signed [7:0] out_frac;

  perceptron #(
    .NUM_INPUTS(1), .DATA_WIDTH(8), .Q_FRAC(15), .RELU(0),
    .WEIGHTS(W_NEG1), .BIAS(8'sd0), .SCALE(24'sd1 <<< 14)
  ) dut_frac (.inputs(in_frac), .out(out_frac));

  // =====================================================================
  //  3. negative bias, ReLU off: checks PROD_WIDTH'(BIAS) sign extension
  // =====================================================================
  localparam logic signed [7:0] W_POS1 [1] = '{8'sd1};
  logic signed [7:0] in_bias [1];
  logic signed [7:0] out_bias;

  perceptron #(
    .NUM_INPUTS(1), .DATA_WIDTH(8), .Q_FRAC(15), .RELU(0),
    .WEIGHTS(W_POS1), .BIAS(-8'sd100), .SCALE(24'sd1 <<< 15)
  ) dut_bias (.inputs(in_bias), .out(out_bias));

  // =====================================================================
  //  4/5. saturation and the RELU parameter
  // =====================================================================
  localparam logic signed [7:0] W_BIG_P [2] = '{ 8'sd100,  8'sd100};
  localparam logic signed [7:0] W_BIG_N [2] = '{-8'sd100, -8'sd100};
  logic signed [7:0] in_sat [2];
  logic signed [7:0] out_sat_hi, out_sat_lo, out_relu_on;

  perceptron #(
    .NUM_INPUTS(2), .DATA_WIDTH(8), .Q_FRAC(0), .RELU(0),
    .WEIGHTS(W_BIG_P), .BIAS(8'sd0), .SCALE(24'sd1)
  ) dut_sat_hi (.inputs(in_sat), .out(out_sat_hi));

  perceptron #(
    .NUM_INPUTS(2), .DATA_WIDTH(8), .Q_FRAC(0), .RELU(0),
    .WEIGHTS(W_BIG_N), .BIAS(8'sd0), .SCALE(24'sd1)
  ) dut_sat_lo (.inputs(in_sat), .out(out_sat_lo));

  perceptron #(
    .NUM_INPUTS(2), .DATA_WIDTH(8), .Q_FRAC(0), .RELU(1),
    .WEIGHTS(W_BIG_N), .BIAS(8'sd0), .SCALE(24'sd1)
  ) dut_relu_on (.inputs(in_sat), .out(out_relu_on));

  // =====================================================================
  //  6/7. real layer-0 geometry: 40 inputs, 24 bit, SCALE = 883
  // =====================================================================
  localparam int  N_WIDE     = 40;
  localparam int  DW_WIDE    = 24;
  localparam longint signed SCALE_WIDE = 883;   // round(8.21954681e-7 * 2**30)

  localparam logic signed [7:0] W_WIDE [N_WIDE] = '{default: 8'sd127};
  logic signed [DW_WIDE-1:0] in_wide [N_WIDE];
  logic signed [DW_WIDE-1:0] out_wide;

  perceptron #(
    .NUM_INPUTS(N_WIDE), .DATA_WIDTH(DW_WIDE), .Q_FRAC(15), .RELU(1),
    .WEIGHTS(W_WIDE), .BIAS(24'sd0), .SCALE(24'sd883)
  ) dut_wide (.inputs(in_wide), .out(out_wide));

  function automatic longint signed wide_sum();
    longint signed s;
    s = 0;
    for (int i = 0; i < N_WIDE; i++)
      s += longint'(in_wide[i]) * 127;
    return s;
  endfunction

  // =====================================================================
  initial begin
    longint signed exp;

    $display("=== perceptron_tb_fixedpoint ===");

    // ---- 1. unity scale --------------------------------------------
    $display("[1] unity scale, ReLU on");
    in_unity[0] = 8'sd40; in_unity[1] = 8'sd15; #5;
    check("ReLU(40-15)", out_unity, golden(25, 32768, 0, 15, 1, 8));
    in_unity[0] = 8'sd15; in_unity[1] = 8'sd40; #5;
    check("ReLU(15-40)", out_unity, golden(-25, 32768, 0, 15, 1, 8));

    // ---- 2. fractional scale, floor of a negative ------------------
    $display("[2] scale = 0.5, ReLU off (arithmetic shift floors)");
    in_frac[0] = 8'sd3; #5;                       // sum = -3, -3*0.5 = -1.5
    check("floor(-1.5)", out_frac, golden(-3, 16384, 0, 15, 0, 8));
    in_frac[0] = -8'sd3; #5;                      // sum = +3, +3*0.5 = +1.5
    check("floor(+1.5)", out_frac, golden(3, 16384, 0, 15, 0, 8));

    // ---- 3. negative bias sign extension ---------------------------
    $display("[3] negative bias, ReLU off");
    in_bias[0] = 8'sd50; #5;
    check("50 + (-100)", out_bias, golden(50, 32768, -100, 15, 0, 8));

    // ---- 4/5. saturation and RELU ----------------------------------
    $display("[4] saturation, [5] RELU parameter");
    in_sat[0] = 8'sd100; in_sat[1] = 8'sd100; #5;
    check("sat high (+20000)", out_sat_hi,  golden( 20000, 1, 0, 0, 0, 8));
    check("sat low  (-20000)", out_sat_lo,  golden(-20000, 1, 0, 0, 0, 8));
    check("RELU(-20000)",      out_relu_on, golden(-20000, 1, 0, 0, 1, 8));

    // ---- 6. wide-product regression --------------------------------
    $display("[6] 40 x 24-bit, SCALE = 883 (layer-0 geometry)");
    foreach (in_wide[i]) in_wide[i] = 24'sd39370;
    #5;
    exp = golden(wide_sum(), SCALE_WIDE, 0, 15, 1, DW_WIDE);
    check("sum=199999600", out_wide, exp);
    if (out_wide == 0)
      $display("      NOTE: a 0 here is the old 38-bit product wrapping negative");

    foreach (in_wide[i]) in_wide[i] = 24'sd8388607;   // worst case, saturates
    #5;
    check("worst case (sat)", out_wide,
          golden(wide_sum(), SCALE_WIDE, 0, 15, 1, DW_WIDE));

    // ---- 7. randomised sweep ---------------------------------------
    $display("[7] 500 random layer-0 vectors");
    begin
      int fails_before;
      fails_before = error_count;   // must be a statement: a declaration
                                    // initializer here has static lifetime
                                    // and would run once at time 0
      for (int t = 0; t < 500; t++) begin
        foreach (in_wide[i])
          in_wide[i] = $urandom_range(0, 8388607);
        #5;
        exp = golden(wide_sum(), SCALE_WIDE, 0, 15, 1, DW_WIDE);
        if (out_wide !== exp[DW_WIDE-1:0]) begin
          $error("[RANDOM FAIL] trial %0d | expected %0d | got %0d",
                 t, exp, out_wide);
          error_count++;
          if (error_count - fails_before > 5) begin
            $display("      (stopping after 5 random failures)");
            break;
          end
        end
      end
      if (error_count == fails_before)
        $display("  ok  500/500 random vectors matched");
    end

    $display("---------------------------------------------");
    if (error_count == 0)
      $display("SUCCESS: fixed-point behaviour verified!");
    else
      $display("FAILURE: %0d errors found.", error_count);

    $finish;
  end

endmodule
