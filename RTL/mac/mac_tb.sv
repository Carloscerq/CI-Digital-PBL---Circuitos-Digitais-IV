module mac_tb ();

  timeunit      1ns;
  timeprecision 1ps;

  localparam int DW  = 24;
  localparam int WW  = 8;
  localparam int SW  = 40;

  localparam int MAX_TAPS = 132;

  logic clk = 1'b0;
  always #1 clk = ~clk;

  logic reset = 1'b1;
  logic load  = 1'b0;
  logic en    = 1'b0;

  logic signed [DW-1:0] data   = '0;
  logic signed [WW-1:0] weight = '0;
  logic signed [SW-1:0] acc;

  mac #(.DATA_WIDTH(DW), .WEIGHT_WIDTH(WW), .SUM_WIDTH(SW)) dut (
    .clk    (clk),
    .reset  (reset),
    .load   (load),
    .en     (en),
    .data   (data),
    .weight (weight),
    .acc    (acc)
  );

  localparam int NDW = 8, NWW = 4, NSW = 16;

  logic signed [NDW-1:0] n_data   = '0;
  logic signed [NWW-1:0] n_weight = '0;
  logic signed [NSW-1:0] n_acc;
  logic                  n_load = 1'b0, n_en = 1'b0;

  mac #(.DATA_WIDTH(NDW), .WEIGHT_WIDTH(NWW), .SUM_WIDTH(NSW)) dut_narrow (
    .clk    (clk),
    .reset  (reset),
    .load   (n_load),
    .en     (n_en),
    .data   (n_data),
    .weight (n_weight),
    .acc    (n_acc)
  );

  int error_count = 0;
  int check_count = 0;

  task automatic check(input string name, input longint got, input longint exp);
    check_count++;
    assert (got === exp)
      else begin
        $error("[%s FAIL] expected %0d, got %0d", name, exp, got);
        error_count++;
      end
  endtask

  logic signed [DW-1:0] td [MAX_TAPS];
  logic signed [WW-1:0] tw [MAX_TAPS];

  task automatic run_dot(input int n, output longint exp);
    exp = 0;
    for (int i = 0; i < n; i++) begin
      @(negedge clk);
      data   = td[i];
      weight = tw[i];
      load   = (i == 0);      // first tap replaces, the rest accumulate
      en     = 1'b1;
      exp   += longint'(td[i]) * longint'(tw[i]);
    end
    // one more negedge: the posedge in between latched the final tap
    @(negedge clk);
    load = 1'b0;
    en   = 1'b0;
  endtask

  task automatic fill_random(input int n);
    for (int i = 0; i < n; i++) begin
      td[i] = DW'($urandom);   // full-range patterns, so both signs are covered
      tw[i] = WW'($urandom);
    end
  endtask

  // --------------------------------------------------------------- the test
  int      lengths [6] = '{1, 2, 4, 8, 33, MAX_TAPS};
  longint  exp, exp2;

  initial begin
    $display("=== mac_tb : %0dx%0d MAC with a %0d-bit accumulator ===", DW, WW, SW);

    // ---- reset ----------------------------------------------------------
    repeat (2) @(negedge clk);
    check("RESET", longint'(acc), 0);
    reset = 1'b0;
    @(negedge clk);

    // ---- directed: a hand-checkable dot product -------------------------
    // 3*4 + (-5)*6 + 7*(-2) = 12 - 30 - 14 = -32
    td[0] =  24'sd3; tw[0] =  8'sd4;
    td[1] = -24'sd5; tw[1] =  8'sd6;
    td[2] =  24'sd7; tw[2] = -8'sd2;
    run_dot(3, exp);
    check("DIRECTED", longint'(acc), -32);
    check("DIRECTED_MODEL", exp, -32);

    // ---- hold: with load and en low the accumulator must not move -------
    repeat (5) begin
      @(negedge clk);
      data   = 24'sd12345;      // wiggle the datapath to prove it is ignored
      weight = 8'sd77;
    end
    @(negedge clk);
    check("HOLD", longint'(acc), -32);

    // ---- load restarts a dot product without needing a reset ------------
    td[0] = 24'sd10; tw[0] = 8'sd10;
    run_dot(1, exp);
    check("LOAD_RESTART", longint'(acc), 100);

    // ---- random dot products at every interesting length ----------------
    foreach (lengths[k]) begin
      for (int trial = 0; trial < 40; trial++) begin
        fill_random(lengths[k]);
        run_dot(lengths[k], exp);
        check($sformatf("RANDOM_n%0d", lengths[k]), longint'(acc), exp);
      end
    end

    // ---- worst case magnitude: 132 taps of the most negative operands ---
    // (-2**23) * (-128) * 132 = 2**37.05, which must still fit in SW=40 bits
    for (int i = 0; i < MAX_TAPS; i++) begin
      td[i] = -(24'sd1 <<< (DW-1));   // -8388608
      tw[i] = -(8'sd1  <<< (WW-1));   // -128
    end
    run_dot(MAX_TAPS, exp);
    check("SAT_MAX_POS", longint'(acc), exp);

    // and the same magnitude with the opposite sign
    for (int i = 0; i < MAX_TAPS; i++) begin
      td[i] =  (24'sd1 <<< (DW-1)) - 1;
      tw[i] = -(8'sd1  <<< (WW-1));
    end
    run_dot(MAX_TAPS, exp);
    check("SAT_MAX_NEG", longint'(acc), exp);

    // ---- zero weights must not disturb the running sum ------------------
    // (mlp.sv feeds weight 0 to the idle MACs during layers 1 and 2)
    for (int i = 0; i < 16; i++) begin
      td[i] = 24'sd123456;
      tw[i] = (i == 0) ? 8'sd3 : 8'sd0;
    end
    run_dot(16, exp);
    check("ZERO_WEIGHTS", longint'(acc), 24'sd123456 * 3);

    // ---- the narrow instance --------------------------------------------
    // 8 taps of 8x4, worst case 8 * 128 * 8 = 8192, inside SW=16
    exp2 = 0;
    for (int i = 0; i < 8; i++) begin
      @(negedge clk);
      n_data   = NDW'($urandom);
      n_weight = NWW'($urandom);
      n_load   = (i == 0);
      n_en     = 1'b1;
      exp2    += longint'(n_data) * longint'(n_weight);
    end
    @(negedge clk);
    n_load = 1'b0;
    n_en   = 1'b0;
    check("NARROW_8x4", longint'(n_acc), exp2);

    // ---- synchronous reset during an accumulation ------------------------
    // reset is sampled on the rising edge like every other input, so it has to
    // be held across a posedge to clear the accumulator, and it outranks the
    // load/en that run_dot is still driving
    fill_random(MAX_TAPS);
    fork
      run_dot(MAX_TAPS, exp);
      begin
        repeat (20) @(negedge clk);
        reset = 1'b1;
        @(negedge clk);       // the posedge in between clears the accumulator
        check("SYNC_RESET", longint'(acc), 0);
        reset = 1'b0;
      end
    join

    $display("-----------------------------------------------------");
    $display("  checks              : %0d", check_count);
    $display("  errors              : %0d", error_count);
    if (error_count == 0)
      $display("SUCCESS: mac matches the 64-bit reference on every dot product.");
    else
      $display("FAILURE: %0d assertion errors encountered.", error_count);

    $finish;
  end

endmodule
