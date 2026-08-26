// Wires spi_controller to N_SLAVES real spi_slave instances over one shared
// bus and checks every transfer in both directions: the master word has to
// reach the addressed slave and the slave word has to reach the master, in the
// same exchange.
//
// The two slaves are deliberately configured differently, a mode 0 device and
// a slower mode 3 one, so the per slave CPOL/CPHA/CLK_DIV arrays are actually
// exercised. Multi word transactions are checked too: the select has to stay
// down for the whole transaction and go back up exactly once at the end.
//
// CLK_DIV has to stay >= 4 for every slave: spi_slave oversamples the pins on
// clk and needs the half period to be longer than its synchroniser latency.
//
// The checks below are immediate assertions, which verilator only evaluates
// when it is given --assert. Without that flag the run reports success no
// matter what came off the bus.
module spi_controller_tb ();

  localparam int SIZE     = 8;
  localparam int N_SLAVES = 2;

  // slave 0: mode 0, fast.  slave 1: mode 3, slower.
  localparam int CLK_DIV [N_SLAVES] = '{4, 6};
  localparam bit CPOL    [N_SLAVES] = '{1'b0, 1'b1};
  localparam bit CPHA    [N_SLAVES] = '{1'b0, 1'b1};

  localparam int ADDR_W = (N_SLAVES > 1) ? $clog2(N_SLAVES) : 1;

  logic clk = 1'b0;
  logic reset_n;

  always #5 clk = ~clk;

  // Below this the slave answers too late and the master reads the previous
  // bit on miso, so fail loudly instead of printing a puzzling mismatch.
  initial
    for (int s = 0; s < N_SLAVES; s++)
      if (CLK_DIV[s] < 4)
        $fatal(1, "spi_slave needs CLK_DIV >= 4, slave %0d has %0d",
               s, CLK_DIV[s]);

  // fabric side of the controller
  logic [SIZE-1:0]   data_in;
  logic [ADDR_W-1:0] address;
  logic              start;
  logic              hold_select;
  logic              ready;
  logic [SIZE-1:0]   data_out;
  logic              data_valid;
  // pins
  logic                serial_clock;
  logic                mosi;
  logic                miso;
  logic [N_SLAVES-1:0] slave_select_n;

  spi_controller #(
    .SIZE(SIZE),
    .AMOUNT_OF_SLAVES(N_SLAVES),
    .CLK_DIV(CLK_DIV),
    .CPOL(CPOL),
    .CPHA(CPHA)
  ) controller (
    .clk(clk),
    .reset_n(reset_n),
    .data_in(data_in),
    .address(address),
    .start(start),
    .hold_select(hold_select),
    .ready(ready),
    .data_out(data_out),
    .data_valid(data_valid),
    .serial_clock(serial_clock),
    .slave_in_controller_out(mosi),
    .controller_in_slave_out(miso),
    .slave_select_n(slave_select_n)
  );

  // fabric side of each slave
  logic [SIZE-1:0] slave_data_in  [N_SLAVES];
  logic [SIZE-1:0] slave_data_out [N_SLAVES];
  logic            slave_valid    [N_SLAVES];
  logic            slave_busy     [N_SLAVES];
  logic            slave_miso     [N_SLAVES];

  genvar s;
  generate
    for (s = 0; s < N_SLAVES; s++) begin : slaves
      spi_slave #(
        .SIZE(SIZE),
        .CPOL(CPOL[s]),
        .CPHA(CPHA[s])
      ) u_slave (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(slave_data_in[s]),
        .data_out(slave_data_out[s]),
        .data_valid(slave_valid[s]),
        .busy(slave_busy[s]),
        .serial_clock(serial_clock),
        .slave_in_controller_out(mosi),
        .controller_in_slave_out(slave_miso[s]),
        .slave_select_n(slave_select_n[s])
      );
    end
  endgenerate

  // only the selected slave drives the shared miso line
  always_comb begin
    miso = 1'b0;
    for (int s = 0; s < N_SLAVES; s++)
      if (!slave_select_n[s]) miso = slave_miso[s];
  end

  // what each slave received, latched on its own data_valid pulse
  logic [SIZE-1:0] slave_rx    [N_SLAVES];
  int              slave_words [N_SLAVES];

  initial begin
    for (int s = 0; s < N_SLAVES; s++) begin
      slave_rx[s]    = '0;
      slave_words[s] = 0;
    end
  end

  always_ff @(posedge clk) begin
    for (int s = 0; s < N_SLAVES; s++)
      if (slave_valid[s]) begin
        slave_rx[s]    <= slave_data_out[s];
        slave_words[s] <= slave_words[s] + 1;
      end
  end

  // Counts how often the bus goes fully idle. A transaction of any length may
  // only do that once, right at its end.
  logic all_released;
  logic all_released_q = 1'b1;
  int   select_rises   = 0;

  assign all_released = &slave_select_n;

  always_ff @(posedge clk) begin
    all_released_q <= all_released;
    if (all_released && !all_released_q) select_rises <= select_rises + 1;
  end

  int error_count = 0;

  // One full duplex exchange with the given slave, checked in both
  // directions. Stimulus moves on the falling edge, the RTL samples on the
  // rising one. With hold set the select stays down afterwards, and
  // next_slave_word is what the slave should answer with on the next word.
  task automatic exchange(input int slave,
                          input logic [SIZE-1:0] master_word,
                          input logic [SIZE-1:0] slave_word,
                          input bit hold = 1'b0,
                          input logic [SIZE-1:0] next_slave_word = '0);
    int words_before [N_SLAVES];
    for (int s = 0; s < N_SLAVES; s++) words_before[s] = slave_words[s];

    @(negedge clk);
    // the slave latches data_in when its select falls, so it has to be up
    // before the transfer starts
    slave_data_in[slave] = slave_word;

    assert (ready)
      else begin
        $error("[FAIL] controller not ready before start");
        error_count++;
      end

    data_in     = master_word;
    address     = ADDR_W'(slave);
    start       = 1'b1;
    hold_select = hold;
    @(negedge clk);
    start       = 1'b0;
    hold_select = 1'b0;

    // The slave reloads its transmit register the moment a word completes, so
    // the answer for a following word has to be up well before that, the same
    // one word budget its fabric would have on real hardware. Wait for it to
    // have taken this word first, otherwise the new value lands before the
    // falling select has latched the current one.
    if (hold) begin
      do @(negedge clk); while (!slave_busy[slave]);
      repeat (2) @(negedge clk); // busy leads the load by a cycle
      slave_data_in[slave] = next_slave_word;
    end

    // data_valid pulses for one clk with the received word on data_out
    do @(negedge clk); while (!data_valid);
    // let the slave side settle, it runs a few clks behind the pins
    repeat (2) @(negedge clk);

    $display("  slave %0d | master sent %02h got %02h | slave sent %02h got %02h%s",
             slave, master_word, data_out, slave_word, slave_rx[slave],
             hold ? " | select held" : "");

    assert (data_out === slave_word)
      else begin
        $error("[FAIL] slave %0d -> master: expected %02h, got %02h",
               slave, slave_word, data_out);
        error_count++;
      end

    assert (slave_rx[slave] === master_word)
      else begin
        $error("[FAIL] master -> slave %0d: expected %02h, got %02h",
               slave, master_word, slave_rx[slave]);
        error_count++;
      end

    // the addressed slave took exactly one word, the others took none
    for (int s = 0; s < N_SLAVES; s++) begin
      int expected;
      expected = words_before[s] + ((s == slave) ? 1 : 0);
      assert (slave_words[s] == expected)
        else begin
          $error("[FAIL] slave %0d received %0d words during a transfer to %0d, expected %0d",
                 s, slave_words[s] - words_before[s], slave, expected - words_before[s]);
          error_count++;
        end
    end

    if (hold)
      assert (!slave_select_n[slave])
        else begin
          $error("[FAIL] select released mid transaction with slave %0d", slave);
          error_count++;
        end
    else
      assert (&slave_select_n)
        else begin
          $error("[FAIL] slave still selected after the transfer: %b",
                 slave_select_n);
          error_count++;
        end
  endtask

  // A whole transaction: every word but the last goes out holding the select,
  // so the bus may only go idle once, at the end.
  task automatic transaction(input int slave,
                             input logic [SIZE-1:0] words   [],
                             input logic [SIZE-1:0] answers []);
    int rises_before;
    rises_before = select_rises;

    $display("  -- %0d word transaction with slave %0d --", words.size(), slave);

    for (int w = 0; w < words.size(); w++)
      exchange(slave, words[w], answers[w],
               w != words.size() - 1,
               (w + 1 < answers.size()) ? answers[w+1] : '0);

    assert (select_rises == rises_before + 1)
      else begin
        $error("[FAIL] select went idle %0d times during one transaction, expected 1",
               select_rises - rises_before);
        error_count++;
      end
  endtask

  initial begin
    reset_n     = 1'b0;
    start       = 1'b0;
    hold_select = 1'b0;
    data_in     = '0;
    address     = '0;
    for (int s = 0; s < N_SLAVES; s++) slave_data_in[s] = '0;
    repeat (4) @(negedge clk);
    reset_n = 1'b1;

    $display("=== spi_controller_tb : %0d bits, %0d slaves ===", SIZE, N_SLAVES);
    for (int s = 0; s < N_SLAVES; s++)
      $display("  slave %0d: mode %0d%0d, CLK_DIV %0d",
               s, CPOL[s], CPHA[s], CLK_DIV[s]);

    // single word transfers, alternating between the two configurations
    exchange(0, 8'hA5, 8'h5A);
    exchange(1, 8'h01, 8'h80);
    exchange(0, 8'hFF, 8'h00);
    exchange(1, 8'h00, 8'hFF);
    exchange(0, 8'h3C, 8'hC3);
    exchange(1, 8'h12, 8'h34);

    // back to back random words, with no idle time in between
    for (int i = 0; i < 4; i++)
      exchange(i % N_SLAVES, SIZE'($urandom), SIZE'($urandom));

    // multi word transactions, the shape a screen or a sensor register access
    // actually needs: command byte then payload, select down throughout
    transaction(0, '{8'h2A, 8'h00, 8'h1F}, '{8'hAA, 8'hBB, 8'hCC});
    transaction(1, '{8'h9F, 8'h00}, '{8'hEF, 8'h40});
    transaction(0, '{8'h11, 8'h22, 8'h33, 8'h44}, '{8'h55, 8'h66, 8'h77, 8'h88});

    // a plain transfer still works after a held one
    exchange(1, 8'h7E, 8'hE7);

    if (error_count == 0)
      $display("SUCCESS: every word made it across in both directions!");
    else
      $display("FAILURE: %0d assertion errors encountered.", error_count);

    $finish;
  end

  // safety net, a transfer takes about 2*SIZE*CLK_DIV clks
  initial begin
    #200000;
    $error("FAILURE: timeout, the controller never raised data_valid.");
    $finish;
  end

endmodule
