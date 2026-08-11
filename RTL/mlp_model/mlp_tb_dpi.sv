module mlp_tb_dpi ();

  import mlp_weights_pkg::*;

  // -------- reference model, scalars only across the boundary --------
  import "DPI-C" function void   ref_set_input(input int idx, input int val);
  import "DPI-C" function void   ref_run();
  import "DPI-C" function int    ref_get_logit(input int idx);
  import "DPI-C" function int    ref_get_class();
  import "DPI-C" function int    ref_get_saturated();
  import "DPI-C" function int    ref_get_float_class();
  import "DPI-C" function real   ref_get_float_logit(input int idx);
  import "DPI-C" function int    ref_get_scale(input int layer);

  logic clk = 1'b0;
  always #1 clk = ~clk;

  logic signed [23:0] features  [N_IN];
  logic signed [23:0] logits    [N_OUT];
  logic        [1:0]  class_idx;

  mlp dut (
    .clk       (clk),
    .features  (features),
    .logits    (logits),
    .class_idx (class_idx)
  );

  function automatic string cname(input int c);
    case (c)
      0: return "Bearing";
      1: return "Misalign";
      2: return "None";
      3: return "Unbalance";
      default: return "?";
    endcase
  endfunction

  int n_vectors = 1000;
  int err_logit, err_class, n_sat, n_quant;
  int hist [4];

  // push the current `features` into the reference and evaluate it
  task automatic run_reference();
    for (int i = 0; i < N_IN; i++)
      ref_set_input(i, int'(features[i]));
    ref_run();
  endtask

  // features[0..N_BINS-1] are |rFFT| bins after the LMS, so they are signed and in
  // practice stay inside ~12 bits; features[N_BINS..N_IN-1] are the frame aggregates
  // already shifted by EXTRA_SHIFT (temperatures ~200..270, current power ~75..125,
  // mdc_k0 0..64 -- the ranges the notebook printed for the hardware bus).
  task automatic randomise_features(input int vec_num);
    int mag, peaks;
    case (vec_num)
      0: foreach (features[i]) features[i] = 24'sd0;              // silence
      1: foreach (features[i]) features[i] = 24'sd1;              // tiny
      2: foreach (features[i]) features[i] = 24'sd8388607;        // saturating
      3: foreach (features[i]) features[i] = -24'sd8388608;       // saturating, negative
      4: begin                                                    // one hot bin
           foreach (features[i]) features[i] = 24'sd0;
           features[7] = 24'sd50000;
         end
      5: begin                                                    // last bin, negative
           foreach (features[i]) features[i] = 24'sd0;
           features[N_BINS-1] = -24'sd50000;
         end
      6: begin                                                    // aggregates only
           foreach (features[i]) features[i] = 24'sd0;
           for (int i = N_BINS; i < N_IN; i++) features[i] = 24'sd255;
         end
      default: begin
        // most frames inside the measured range, one in eight pushed to the top of
        // the bus so the saturation path keeps being exercised
        mag = 1 << ((vec_num % 8 == 0) ? $urandom_range(12, 22) : $urandom_range(4, 11));
        for (int i = 0; i < N_BINS; i++)
          features[i] = 24'($urandom_range(0, mag)) - 24'(mag/4);
        peaks = $urandom_range(1, 3);
        for (int p = 0; p < peaks; p++)
          features[$urandom_range(0, N_BINS-1)] =
            24'($urandom_range(mag, (mag*8 > 8388607) ? 8388607 : mag*8));
        features[N_BINS+0] = 24'($urandom_range(190, 275));   // Temperature_housing_A
        features[N_BINS+1] = 24'($urandom_range(190, 275));   // Temperature_housing_B
        features[N_BINS+2] = 24'($urandom_range( 70, 130));   // U-phase_pow
        features[N_BINS+3] = 24'($urandom_range(  0,  64));   // mdc_k0
      end
    endcase
  endtask

  initial begin
    int ref_class, ref_float_class;

    err_logit = 0; err_class = 0; n_sat = 0; n_quant = 0;
    foreach (hist[i]) hist[i] = 0;

    void'($value$plusargs("n_vectors=%d", n_vectors));

    $display("=== mlp_tb_dpi : %0d vectors against mlp_ref.cpp ===", n_vectors);
    $display("MODEL  %0d inputs (%0d bins + %0d aggregates) -> %0d -> %0d -> %0d",
             N_IN, N_BINS, N_EXTRA, N_H0, N_H1, N_OUT);

    // the reference derives these from mlp_weights.h; the package hard-codes
    // them. Disagreement here means the package was regenerated incorrectly.
    $display("SCALE  package: L0=%0d L1=%0d L2=%0d",
             L0_SCALE[0], L1_SCALE[0], L2_SCALE[0]);
    $display("SCALE  C++ ref: L0=%0d L1=%0d L2=%0d",
             ref_get_scale(0), ref_get_scale(1), ref_get_scale(2));
    assert (L0_SCALE[0] == ref_get_scale(0) &&
            L1_SCALE[0] == ref_get_scale(1) &&
            L2_SCALE[0] == ref_get_scale(2))
      else $error("[SCALE] package and reference disagree -- regenerate the package");

    for (int v = 0; v < n_vectors; v++) begin
      randomise_features(v);

      @(posedge clk);
      #0;                                   // let the combinational cone settle
      run_reference();

      ref_class       = ref_get_class();
      ref_float_class = ref_get_float_class();
      hist[ref_class]++;
      if (ref_get_saturated() != 0) n_sat++;

      for (int j = 0; j < N_OUT; j++)
        assert (int'(logits[j]) === ref_get_logit(j))
          else begin
            $error("[LOGIT] vec %0d, logit %0d: reference %0d, RTL %0d",
                   v, j, ref_get_logit(j), int'(logits[j]));
            err_logit++;
          end

      assert (int'(class_idx) === ref_class)
        else begin
          $error("[CLASS] vec %0d: reference %0d (%s), RTL %0d (%s)",
                 v, ref_class, cname(ref_class),
                 int'(class_idx), cname(int'(class_idx)));
          err_class++;
        end

      // fixed vs float disagreement is quantisation, not an RTL fault
      if (ref_class != ref_float_class) begin
        n_quant++;
        if (n_quant <= 10)
          $display("  note: vec %0d fixed=%s float=%s (float logits %.3f %.3f %.3f %.3f)",
                   v, cname(ref_class), cname(ref_float_class),
                   ref_get_float_logit(0), ref_get_float_logit(1),
                   ref_get_float_logit(2), ref_get_float_logit(3));
      end
    end

    $display("-----------------------------------------------------");
    $display("  vectors             : %0d", n_vectors);
    $display("  logit mismatches    : %0d", err_logit);
    $display("  class mismatches    : %0d", err_class);
    $display("  quantisation notes  : %0d", n_quant);
    $display("  saturating vectors  : %0d", n_sat);
    $display("  predicted classes   : %s=%0d %s=%0d %s=%0d %s=%0d",
             cname(0), hist[0], cname(1), hist[1],
             cname(2), hist[2], cname(3), hist[3]);
    if (hist[2] == 0) begin
      $display("  WARNING: the 'None' class was never predicted -- random spectra");
      $display("           cannot reach it. Feed real feature rows to cover it.");
    end
    if (err_logit + err_class == 0)
      $display("SUCCESS: RTL matches the C++ reference bit-exactly.");
    else
      $display("FAILURE: %0d mismatches.", err_logit + err_class);

    $finish;
  end

endmodule
