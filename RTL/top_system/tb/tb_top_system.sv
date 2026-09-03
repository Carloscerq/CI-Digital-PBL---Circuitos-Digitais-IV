`timescale 1ns / 1ps

// ============================================================================
// tb_top_system -- full-chain testbench for the top_system integration
// ============================================================================
// Drives the one and only input of the DUT (the UART pin) with synthetic
// sensor frames built from recorded vibration data, then watches the decision
// outputs and the sticky error bus.
//
// >>> SIM_BAUD_NOTE <<<
// One CNN verdict costs 65_536 UART frames:
//
//   32 (FIR decimation) x 64 (HOP_SIZE) = 2_048 frames per FFT round
//   32 rounds (SPEC_FRAMES)             = 65_536 frames per spectrogram
//
// At the production 115_200 baud a frame is 24 bytes x 10 bits x 434 clocks =
// 104_167 clocks, so a single classification would take 6.8e9 clocks. That is
// not simulatable. BAUD_RATE is therefore raised for simulation, which shrinks
// the frame to 7_680 clocks and the run to ~5.0e8 clocks (~10 s of simulated
// time at 50 MHz).
//
// The floor is set by baudrate.sv: RX_ACC_MAX = CLK_FREQ_HZ/(BAUD_RATE*16)
// must stay >= 2, because RX_ACC_WIDTH = $clog2(RX_ACC_MAX) and a value of 1
// yields a zero-width accumulator. BAUD_RATE = 1_562_500 gives RX_ACC_MAX = 2,
// i.e. 32 clocks per bit -- the fastest legal setting.
//
// This changes only the baud divisor. The receiver FSM, its 16x oversampling,
// the mid-bit sampling point and the framing layer all run identically. Use
// MODE = "uart" with -GBAUD_RATE=115200 to prove the production divisor.
//
// >>> DATA_RATE_NOTE <<<
// Frames are sent back to back by default, which is 13.5x the production
// arrival rate of 480 frames/s. The pipeline has room for this (an FFT round
// happens every 2_048 frames and the vibration FIFO holds 64), but if
// error_status[ERR_VIB_OVERRUN] ever sets, re-run with +FRAME_GAP=<clocks>
// before concluding the RTL is at fault -- an overrun at 13.5x tells you
// nothing about behaviour at 1x.
//
// >>> AUX_NOTE <<<
// A frame carries all seven sensor words: 4 vibration, then 1 current, then
// 2 temperature (word order fixed by AUX_BASE and EXTRA_SEL '{1,2,0}, i.e.
// aux 0 = current U-phase, aux 1 = temperature A, aux 2 = temperature B).
//
// The three non-vibration words are NOT raw samples. fft_to_mlp_collector
// feeds them to the MLP through EXTRA_SHIFT = {-6,-6,-5}, and mlp_weights was
// trained on frame AGGREGATES scaled by 2^9:
//
//   word 5,6 (temperature) = mean(x) over the frame          x 2^9
//   word 4   (current)     = mean(x*x) over the frame        x 2^9
//
// so the host -- this testbench -- must aggregate and rescale. See
// AUX_SCALE_NOTE next to the aggregator for the arithmetic and the ranges
// the model was trained on.
//
// >>> OBSERVABILITY_NOTE <<<
// top_system exposes no result-valid strobe, so the per-inference monitors
// below read dut.mlp_done / dut.cnn_valid through cross-module references.
// Those are simulation-only: every pass/fail criterion is evaluated on real
// top-level ports.
// ============================================================================
module tb_top_system #(
    parameter int CLK_FREQ_HZ = 50_000_000,
    parameter int BAUD_RATE   = 1_562_500,   // see SIM_BAUD_NOTE
    parameter int FIFO_DEPTH  = 64,

    // Backstop only: every normal exit is bounded by the frame budget below.
    // One CNN verdict is ~5.0e8 clocks = ~10 s simulated, so this is ~40x that.
    parameter longint TIMEOUT_NS = 64'd400_000_000_000  // 400 s simulated (sized: unsized literals default to 32 bits)
);

    import system_types_pkg::*;

    // ------------------------------------------------------------------
    // Class map -- must match inference_arbiter / mlp_weights
    // ------------------------------------------------------------------
    localparam int CLASS_BEARING   = 0;
    localparam int CLASS_MISALIGN  = 1;
    localparam int CLASS_NORMAL    = 2;
    localparam int CLASS_UNBALANCE = 3;
    localparam int CLASS_UNKNOWN   = -1;

    // ------------------------------------------------------------------
    // Timing, derived exactly the way the DUT derives it
    // ------------------------------------------------------------------
    localparam int CLK_PERIOD_NS = 20;                        // 50 MHz
    localparam int BIT_CLOCKS    = CLK_FREQ_HZ / BAUD_RATE;
    localparam int FRAME_CLOCKS  = FRAME_BYTES * 10 * BIT_CLOCKS;

    // Frames the pipeline needs before each milestone
    localparam int FRAMES_PER_DECIM = 32;                     // FIR 4*4*2
    localparam int FRAMES_PER_ROUND = FRAMES_PER_DECIM * 64;  // HOP_SIZE = 64
    localparam int FRAMES_PER_SPEC  = FRAMES_PER_ROUND * SPEC_FRAMES;

    // How long to keep clocking after the last frame, waiting for a CNN verdict
    // that is still working its way through the frame buffer and cnn_top.
    localparam int DRAIN_CLOCKS = 4_000_000;        // 80 ms simulated


    // ------------------------------------------------------------------
    // Runtime configuration (plusargs override the defaults)
    // ------------------------------------------------------------------
    string mode      = "stream";                   // "stream" | "uart"
    string scenario  = "0Nm_Normal";
    string data_root = "../../Scripts/process_dataset/dataset_q915";

    int    max_frames  = 0;                        // 0 = derive from targets
    int    cnn_target  = 1;                        // stop after N CNN verdicts
    int    frame_gap   = 0;                        // idle clocks between frames
    bit    strict_class = 0;                       // class mismatch is fatal
    bit    loop_data    = 1;                       // rewind short capture files
    int    progress_every = 2048;

    // Fallback aux values, used only if a capture is missing. These are in the
    // aggregate domain (physical x 2^9, see AUX_SCALE_NOTE), not Q9.15, and are
    // set to the middle of the range the model was trained on.
    int aux_current_dflt = 6  * 512;               // 6.0 A^2 mean power
    int aux_temp0_dflt   = 28 * 512;               // 28.0 degC
    int aux_temp1_dflt   = 29 * 512;               // 29.0 degC

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    logic clk = 1'b0;
    logic reset = 1'b1;
    logic uart_rx = 1'b1;                          // idle high

    logic [2:0]        status_leds;
    logic [N_VIB-1:0]  sensor_fault_mask;
    logic              alert_flag;
    error_status_t     error_status;

    top_system #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .clk              (clk),
        .reset            (reset),
        .uart_rx          (uart_rx),
        .status_leds      (status_leds),
        .sensor_fault_mask(sensor_fault_mask),
        .alert_flag       (alert_flag),
        .error_status     (error_status)
    );

    always #(CLK_PERIOD_NS/2) clk = ~clk;

    longint unsigned cycle = 0;
    always @(posedge clk) cycle <= cycle + 1;

    // ------------------------------------------------------------------
    // Capture files: one streaming reader per sensor word
    // ------------------------------------------------------------------
    // Layout, generalised from the vibration set already in the repo:
    //   <data_root>/vibration/<scenario>/<scenario>_sensor{1..4}.mem
    //   <data_root>/current/<scenario>/<scenario>_sensor{1,2,3}.mem
    //   <data_root>/temperature/<scenario>/<scenario>_sensor{1,2}.mem
    // One 24-bit two's-complement hex word per line, Q9.15.
    //
    // Produced by Scripts/process_dataset/{split_dataset,quantize}.py. Channel
    // order there is TDMS column order, so current sensor1 = U-phase (the only
    // phase present in every run, and the one the model uses) and sensors 2,3
    // are V/W-phase, which the 7-word frame has no slot for.
    // Declared here because next_sample() reports progress with frames_sent.
    int frames_sent      = 0;
    int bad_cksum_frames = 0;

    int      fd       [N_SENSORS];                 // 0 = no file, use fallback
    string   fpath    [N_SENSORS];
    sample_t fallback [N_SENSORS];
    int      wraps    [N_SENSORS];
    bit      present  [N_SENSORS];   // captured at open time; fd[] can go to 0 later

    // ------------------------------------------------------------------
    // Host-side aggregation of the three non-vibration words
    // ------------------------------------------------------------------
    // >>> AUX_SCALE_NOTE <<<
    // fft_to_mlp_collector applies only EXTRA_SHIFT to these words, because
    // mlp_weights was trained on aggregates the host had already scaled by
    // 2^9. Working back from the ranges the training notebook reports for the
    // MLP inputs (temperature 199.7..269.3, U-phase power 75.1..124.1):
    //
    //   MLP input = word >>> -EXTRA_SHIFT   and   MLP input = physical x 2^9 >>> -EXTRA_SHIFT
    //   => word = physical x 2^9,  for all three.
    //
    // The captures are Q9.15 (physical x 2^15), so:
    //   temperature: mean(x_q15)      >> (15 - 9) = >> 6   -> physical x 2^9
    //   current:     mean(x_q15 * x_q15) >> (30 - 9) = >> 21 -> physical x 2^9
    //
    // Feeding a raw Q9.15 sample straight through instead would be 64x too
    // large for temperature, and for current would be a random point on a 50 Hz
    // sinusoid where the model expects its mean square.
    //
    // The block is AGG_SPAN = one FFT round, so exactly one fresh aggregate is
    // published per MLP inference, and it is held for the whole block the way a
    // host with one accumulator per channel would. (The training notebook used
    // a 4096-sample span with a 1024-sample hop; the RTL's decimate-by-32 and
    // HOP_SIZE = 64 give 2048. The aggregates are near-constant within a run --
    // temperature varies ~0.2 degC, current power is stationary -- so the span
    // difference does not move the MLP inputs.)
    localparam int Q_FRAC        = mlp_weights_pkg::Q_FRAC;    // 15
    localparam int AUX_GAIN_LOG2 = 9;                          // host-applied gain
    localparam int TEMP_SHIFT    = Q_FRAC - AUX_GAIN_LOG2;     // 15 - 9  =  6
    localparam int POW_SHIFT     = 2*Q_FRAC - AUX_GAIN_LOG2;   // 30 - 9  = 21
    localparam int AGG_SPAN      = FRAMES_PER_ROUND;           // 2048 frames

    localparam longint SAT_HI =  (64'sd1 <<< (DATA_WIDTH-1)) - 1;
    localparam longint SAT_LO = -(64'sd1 <<< (DATA_WIDTH-1));

    longint  acc_temp [N_TMP];       // running sum of samples
    longint  acc_cur;                // running sum of squares
    int      acc_n;                  // samples in the open block
    sample_t pub_aux  [N_AUX];       // what the frame carries, held per block
    bit      pub_valid;              // a full block has completed

    function automatic sample_t sat24(input longint v);
        if (v > SAT_HI) return sample_t'(SAT_HI);
        if (v < SAT_LO) return sample_t'(SAT_LO);
        return sample_t'(v);
    endfunction

    // Recompute the published words from the first `n` samples of the open
    // block. Slots whose capture is missing keep their constant fallback.
    function automatic void publish_aux(input int n);
        if (n <= 0) return;
        if (present[N_VIB])
            pub_aux[0] = sat24((acc_cur / n) >>> POW_SHIFT);
        for (int t = 0; t < N_TMP; t++)
            if (present[N_VIB + N_CUR + t])
                pub_aux[1 + t] = sat24((acc_temp[t] / n) >>> TEMP_SHIFT);
    endfunction

    function automatic void reset_aggregator();
        acc_cur   = 0;
        acc_n     = 0;
        pub_valid = 1'b0;
        for (int t = 0; t < N_TMP; t++) acc_temp[t] = 0;
        pub_aux[0] = fallback[N_VIB];
        for (int t = 0; t < N_TMP; t++) pub_aux[1 + t] = fallback[N_VIB + N_CUR + t];
    endfunction

    function automatic string sensor_path(input int idx);
        string kind;
        int    n;
        if (idx < N_VIB) begin
            kind = "vibration";
            n    = idx + 1;
        end else if (idx < N_VIB + N_CUR) begin
            kind = "current";
            n    = idx - N_VIB + 1;
        end else begin
            kind = "temperature";
            n    = idx - N_VIB - N_CUR + 1;
        end
        return $sformatf("%s/%s/%s/%s_sensor%0d.mem",
                         data_root, kind, scenario, scenario, n);
    endfunction

    task automatic open_captures();
        int missing = 0;
        for (int i = 0; i < N_SENSORS; i++) fallback[i] = '0;
        fallback[N_VIB + 0] = sample_t'(aux_current_dflt);
        fallback[N_VIB + 1] = sample_t'(aux_temp0_dflt);
        fallback[N_VIB + 2] = sample_t'(aux_temp1_dflt);

        for (int i = 0; i < N_SENSORS; i++) begin
            wraps[i] = 0;
            fpath[i] = sensor_path(i);
            fd[i]    = $fopen(fpath[i], "r");
            present[i] = (fd[i] != 0);
            if (fd[i] == 0) begin
                missing++;
                if (i < N_VIB) begin
                    $display("[TB] FATAL: vibration capture not found: %s", fpath[i]);
                end else begin
                    $display("[TB] aux capture absent, holding constant %0d (aggregate domain, ~%0d physical units): %s",
                             fallback[i], int'(fallback[i]) / 512, fpath[i]);
                end
            end else begin
                $display("[TB] opened %s", fpath[i]);
            end
        end

        for (int i = 0; i < N_VIB; i++)
            if (fd[i] == 0)
                $fatal(1, "[TB] scenario '%s' has no vibration data under %s",
                       scenario, data_root);
        if (missing > 0)
            $display("[TB] NOTE: %0d aux capture(s) missing -- see AUX_NOTE. The MLP verdict is provisional.", missing);

        reset_aggregator();
    endtask

    // Pull the next sample, rewinding at EOF so a short capture can still
    // drive a long run. Returns the fallback if the file is absent.
    function automatic sample_t next_sample(input int idx);
        string line;
        int    code;
        int    got;
        logic [DATA_WIDTH-1:0] raw;

        if (fd[idx] == 0) return fallback[idx];

        for (int attempt = 0; attempt < 2; attempt++) begin
            while (1) begin
                code = $fgets(line, fd[idx]);
                if (code == 0) break;                   // EOF
                got = $sscanf(line, "%h", raw);
                if (got == 1) return sample_t'(raw);
                // blank line or comment: keep going
            end
            // EOF: reopen from the top, or freeze on the fallback
            $fclose(fd[idx]);
            fd[idx] = 0;
            if (!loop_data) begin
                $display("[TB] %s exhausted at frame %0d; holding last value", fpath[idx], frames_sent);
                return fallback[idx];
            end
            wraps[idx]++;
            if (wraps[idx] == 1)
                $display("[TB] NOTE: %s exhausted at frame %0d; rewinding (the wrap is a signal discontinuity)",
                         fpath[idx], frames_sent);
            fd[idx] = $fopen(fpath[idx], "r");
            if (fd[idx] == 0) return fallback[idx];
        end
        return fallback[idx];
    endfunction

    // ------------------------------------------------------------------
    // UART transmitter -- clock-cycle accurate, 8N1, LSB first
    // ------------------------------------------------------------------
    task automatic uart_bit(input logic v);
        uart_rx <= v;
        repeat (BIT_CLOCKS) @(posedge clk);
    endtask

    task automatic uart_byte(input logic [7:0] b);
        uart_bit(1'b0);                              // start
        for (int i = 0; i < 8; i++) uart_bit(b[i]);  // LSB first
        uart_bit(1'b1);                              // stop
    endtask

    // Frame: A5 5A | 7 words x 3 bytes, MSB first | XOR checksum of payload
    task automatic send_frame(input sample_t words [N_SENSORS],
                              input bit corrupt_cksum);
        logic [7:0] payload [FRAME_BYTES-3];
        logic [7:0] cksum;
        int         p;

        p = 0;
        cksum = 8'h00;
        for (int w = 0; w < N_SENSORS; w++) begin
            for (int b = BYTES_PER_WORD - 1; b >= 0; b--) begin
                payload[p] = words[w][b*8 +: 8];
                cksum      = cksum ^ payload[p];
                p++;
            end
        end
        if (corrupt_cksum) begin
            cksum = cksum ^ 8'hFF;
            bad_cksum_frames++;
        end

        uart_byte(8'hA5);
        uart_byte(8'h5A);
        for (int i = 0; i < FRAME_BYTES-3; i++) uart_byte(payload[i]);
        uart_byte(cksum);

        frames_sent++;
        if (frame_gap > 0) repeat (frame_gap) @(posedge clk);
    endtask

    // Words 0..3 carry raw vibration; words 4..6 carry the host aggregates
    // (AUX_SCALE_NOTE). Every capture is advanced once per frame, aggregated or
    // not, so all seven files stay sample-aligned.
    task automatic send_capture_frame(input bit corrupt_cksum);
        sample_t words [N_SENSORS];
        sample_t raw;

        for (int i = 0; i < N_VIB; i++) words[i] = next_sample(i);

        raw      = next_sample(N_VIB);                   // current, U-phase
        acc_cur += longint'(raw) * longint'(raw);
        for (int t = 0; t < N_TMP; t++) begin
            raw = next_sample(N_VIB + N_CUR + t);        // temperature A, B
            acc_temp[t] += longint'(raw);
        end
        acc_n++;

        if (acc_n >= AGG_SPAN) begin
            publish_aux(acc_n);                          // close the block
            pub_valid = 1'b1;
            acc_cur   = 0;
            acc_n     = 0;
            for (int t = 0; t < N_TMP; t++) acc_temp[t] = 0;
        end else if (!pub_valid) begin
            publish_aux(acc_n);                          // warm-up: prefix only
        end

        words[N_VIB] = pub_aux[0];
        for (int t = 0; t < N_TMP; t++)
            words[N_VIB + N_CUR + t] = pub_aux[1 + t];

        send_frame(words, corrupt_cksum);
    endtask

    // ------------------------------------------------------------------
    // Monitors (OBSERVABILITY_NOTE: sim-only cross-module reads)
    // ------------------------------------------------------------------
    int frames_accepted = 0;                       // committed by uart_sensor_frame_rx
    int mlp_results = 0;
    int cnn_results = 0;
    int last_mlp_class = CLASS_UNKNOWN;
    int last_cnn_class = CLASS_UNKNOWN;

    always @(posedge clk) begin
        if (!reset && dut.u_ingestion.sensor_frame_valid) frames_accepted++;
    end

    always @(posedge clk) begin
        if (!reset && dut.mlp_done) begin
            mlp_results++;
            last_mlp_class = int'(dut.mlp_class_idx);
            $display("[%0t] MLP  #%0d  class=%0d (%s)  after %0d frames",
                     $time, mlp_results, last_mlp_class,
                     class_name(last_mlp_class), frames_sent);
        end
    end

    always @(posedge clk) begin
        if (!reset && dut.cnn_valid) begin
            cnn_results++;
            last_cnn_class = argmax4(dut.cnn_bearing, dut.cnn_misalign,
                                     dut.cnn_normal,  dut.cnn_unbalance);
            $display("[%0t] CNN  #%0d  class=%0d (%s)  after %0d frames",
                     $time, cnn_results, last_cnn_class,
                     class_name(last_cnn_class), frames_sent);
            $display("        logits  bearing=%0d misalign=%0d normal=%0d unbalance=%0d",
                     dut.cnn_bearing, dut.cnn_misalign,
                     dut.cnn_normal,  dut.cnn_unbalance);
        end
    end

    // Report each error bit the first time it sets
    error_status_t err_seen = '0;
    always @(posedge clk) begin
        if (!reset && (error_status & ~err_seen) != '0) begin
            for (int b = 0; b < N_ERR; b++)
                if (error_status[b] && !err_seen[b])
                    $display("[%0t] ERROR bit %0d (%s) set after %0d frames",
                             $time, b, err_name(b), frames_sent);
            err_seen <= error_status;
        end
    end

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    function automatic int argmax4(input sample_t bearing, misalign,
                                                normal,  unbalance);
        sample_t best;
        int      idx;
        best = normal;   idx = CLASS_NORMAL;   // tie goes to Normal, as the arbiter does
        if (bearing   > best) begin best = bearing;   idx = CLASS_BEARING;   end
        if (misalign  > best) begin best = misalign;  idx = CLASS_MISALIGN;  end
        if (unbalance > best) begin best = unbalance; idx = CLASS_UNBALANCE; end
        return idx;
    endfunction

    function automatic string class_name(input int c);
        case (c)
            CLASS_BEARING:   return "Bearing";
            CLASS_MISALIGN:  return "Misalign";
            CLASS_NORMAL:    return "Normal";
            CLASS_UNBALANCE: return "Unbalance";
            default:         return "n/a";
        endcase
    endfunction

    function automatic string err_name(input int b);
        case (b)
            ERR_UART_FRAME:  return "UART_FRAME";
            ERR_VIB_OVERRUN: return "VIB_OVERRUN";
            ERR_MLP_DROP:    return "MLP_DROP";
            ERR_SPEC_DESYNC: return "SPEC_DESYNC";
            ERR_MDC_OVERRUN: return "MDC_OVERRUN";
            ERR_CNN_STALL:   return "CNN_STALL";
            default:         return "?";
        endcase
    endfunction

    function automatic string str_lower(input string v);
        string  r;
        byte    c;
        r = v;
        for (int i = 0; i < r.len(); i++) begin
            c = r[i];
            if (c >= "A" && c <= "Z") r[i] = c + 8'd32;
        end
        return r;
    endfunction

    function automatic bit str_contains(input string hay, input string needle);
        int hl = hay.len();
        int nl = needle.len();
        if (nl == 0) return 1'b1;
        if (nl > hl) return 1'b0;
        for (int i = 0; i + nl <= hl; i++)
            if (hay.substr(i, i + nl - 1) == needle) return 1'b1;
        return 1'b0;
    endfunction

    // Scenario name -> expected class. Extend as new captures land.
    function automatic int expected_class(input string s);
        string l = str_lower(s);
        if (str_contains(l, "normal"))                          return CLASS_NORMAL;
        if (str_contains(l, "bpfo")   || str_contains(l, "bpfi") ||
            str_contains(l, "bsf")    || str_contains(l, "bearing"))
                                                                return CLASS_BEARING;
        if (str_contains(l, "misalign"))                        return CLASS_MISALIGN;
        if (str_contains(l, "unbalance") || str_contains(l, "imbalance"))
                                                                return CLASS_UNBALANCE;
        return CLASS_UNKNOWN;
    endfunction

    // True only when every non-vibration capture was actually found, i.e. when
    // the MLP saw 132 real inputs and its verdict can be scored.
    function automatic bit aux_complete();
        for (int i = N_VIB; i < N_SENSORS; i++) if (!present[i]) return 1'b0;
        return 1'b1;
    endfunction

    task automatic apply_reset(input int cycles);
        reset   <= 1'b1;
        uart_rx <= 1'b1;
        repeat (cycles) @(posedge clk);
        reset <= 1'b0;
        repeat (16) @(posedge clk);
    endtask

    task automatic read_config();
        int v;
        void'($value$plusargs("MODE=%s",      mode));
        void'($value$plusargs("SCENARIO=%s",  scenario));
        void'($value$plusargs("DATA_ROOT=%s", data_root));
        if ($value$plusargs("MAX_FRAMES=%d",  v)) max_frames    = v;
        if ($value$plusargs("CNN_TARGET=%d",  v)) cnn_target    = v;
        if ($value$plusargs("FRAME_GAP=%d",   v)) frame_gap     = v;
        if ($value$plusargs("PROGRESS=%d",    v)) progress_every = v;
        if ($test$plusargs("STRICT_CLASS"))       strict_class  = 1;
        if ($test$plusargs("NO_LOOP"))            loop_data     = 0;
    endtask

    // ------------------------------------------------------------------
    // Scoring
    // ------------------------------------------------------------------
    int  health_failures = 0;
    int  class_failures  = 0;

    task automatic check(input bit cond, input string what);
        if (cond) begin
            $display("[TB]   PASS  %s", what);
        end else begin
            $display("[TB]   FAIL  %s", what);
            health_failures++;
        end
    endtask

    // ------------------------------------------------------------------
    // Test bodies
    // ------------------------------------------------------------------
    // Short framing test: proves sync, checksum, resync-on-timeout and the
    // ERR_UART_FRAME path at whatever baud the DUT was built with.
    task automatic run_uart_test();
        sample_t words [N_SENSORS];
        int      base;

        $display("[TB] === MODE uart: framing and error injection ===");
        open_captures();

        $display("[TB] phase 1: 8 clean frames");
        for (int f = 0; f < 8; f++) send_capture_frame(1'b0);
        repeat (64) @(posedge clk);
        check(error_status == '0,
              $sformatf("clean frames leave error_status clear (got %b)", error_status));
        check(frames_accepted == 8,
              $sformatf("all 8 clean frames committed (got %0d)", frames_accepted));

        $display("[TB] phase 2: one frame with a corrupted checksum");
        base = frames_accepted;
        send_capture_frame(1'b1);
        repeat (64) @(posedge clk);
        check(error_status[ERR_UART_FRAME] === 1'b1,
              "bad checksum sets ERR_UART_FRAME");
        check(frames_accepted == base,
              $sformatf("the corrupted frame was NOT committed (accepted %0d, was %0d)",
                        frames_accepted, base));

        $display("[TB] phase 3: truncated frame -> idle timeout resync");
        base = frames_accepted;
        uart_byte(8'hA5);
        uart_byte(8'h5A);
        uart_byte(8'h11);
        // Idle for longer than IDLE_TIMEOUT_BYTES (4 byte times) so the framer
        // gives up mid-frame and goes back to hunting for sync.
        repeat (BIT_CLOCKS * 10 * 8) @(posedge clk);
        check(frames_accepted == base,
              "the truncated frame was NOT committed");

        $display("[TB] phase 4: 8 more clean frames -- the framer must recover");
        for (int i = 0; i < N_SENSORS; i++) words[i] = sample_t'(24'h012345);
        for (int f = 0; f < 8; f++) send_frame(words, 1'b0);
        repeat (64) @(posedge clk);
        check(frames_accepted == base + 8,
              $sformatf("framer resynced and committed 8 more (accepted %0d, expected %0d)",
                        frames_accepted, base + 8));
        check(error_status[ERR_VIB_OVERRUN] === 1'b0,
              "vibration FIFO did not overrun");
        check(!$isunknown({status_leds, sensor_fault_mask, alert_flag}),
              "no X on the decision outputs");

        $display("[TB] frames sent: %0d (%0d deliberately corrupted), accepted: %0d",
                 frames_sent, bad_cksum_frames, frames_accepted);
    endtask

    // Long soak: stream a real capture until the CNN produces cnn_target
    // verdicts, then score health and classification.
    task automatic run_stream_test();
        int     expect_c;
        int     budget;
        int     drain;
        longint est_clocks;

        expect_c = expected_class(scenario);
        budget   = (max_frames > 0)
                 ? max_frames
                 : (FRAMES_PER_SPEC * cnn_target) + FRAMES_PER_ROUND * 2;

        $display("[TB] === MODE stream ===");
        $display("[TB] scenario      : %s (expected class %0d = %s)",
                 scenario, expect_c, class_name(expect_c));
        $display("[TB] baud          : %0d  -> %0d clocks/bit, %0d clocks/frame",
                 BAUD_RATE, BIT_CLOCKS, FRAME_CLOCKS);
        $display("[TB] frames needed : %0d per FFT round, %0d per CNN verdict",
                 FRAMES_PER_ROUND, FRAMES_PER_SPEC);
        est_clocks = longint'(budget) * longint'(FRAME_CLOCKS + frame_gap);
        $display("[TB] frame budget  : %0d  (~%0d clocks, ~%0d ms simulated)",
                 budget, est_clocks, est_clocks / (CLK_FREQ_HZ/1000));
        open_captures();

        while (frames_sent < budget && cnn_results < cnn_target) begin
            send_capture_frame(1'b0);
            if (progress_every > 0 && (frames_sent % progress_every) == 0)
                $display("[%0t] ... %0d/%0d frames, %0d MLP, %0d CNN, err=%b",
                         $time, frames_sent, budget,
                         mlp_results, cnn_results, error_status);
        end

        // Let anything still in flight land. The CNN needs thousands of cycles
        // per frame, so a budget-exhausted run must wait rather than score a
        // verdict that has not arrived yet.
        drain = 0;
        while (drain < DRAIN_CLOCKS && cnn_results < cnn_target) begin
            @(posedge clk);
            drain++;
        end
        repeat (1024) @(posedge clk);
        if (drain >= DRAIN_CLOCKS)
            $display("[TB] drain window (%0d clocks) expired with %0d/%0d CNN verdicts",
                     DRAIN_CLOCKS, cnn_results, cnn_target);

        $display("[TB] --- health ---");
        check(cnn_results >= cnn_target,
              $sformatf("CNN produced %0d/%0d verdicts", cnn_results, cnn_target));
        check(mlp_results >= SPEC_FRAMES * cnn_target,
              $sformatf("MLP produced %0d verdicts (>= %0d expected)",
                        mlp_results, SPEC_FRAMES * cnn_target));
        check(error_status[ERR_UART_FRAME]  === 1'b0, "no UART framing errors");
        check(error_status[ERR_VIB_OVERRUN] === 1'b0,
              "no vibration FIFO overrun (see DATA_RATE_NOTE if this fails)");
        check(error_status[ERR_MLP_DROP]    === 1'b0, "no MLP frame dropped");
        check(error_status[ERR_SPEC_DESYNC] === 1'b0, "spectrogram channels stayed in lockstep");
        check(error_status[ERR_MDC_OVERRUN] === 1'b0, "no MDC overrun");
        check(!$isunknown({status_leds, sensor_fault_mask, alert_flag, error_status}),
              "no X on any top-level output");
        check(status_leds inside {3'b001, 3'b010, 3'b100},
              $sformatf("status_leds is one-hot (%b)", status_leds));
        check(alert_flag === (status_leds != 3'b001),
              "alert_flag agrees with status_leds");
        // ERR_CNN_STALL is reported, not failed: it means the CNN back-pressured
        // the FFT, which is legal and expected once the pipeline is saturated.
        if (error_status[ERR_CNN_STALL])
            $display("[TB]   INFO  ERR_CNN_STALL set -- CNN back-pressured the FFT (not a fault)");

        $display("[TB] --- classification ---");
        if (expect_c == CLASS_UNKNOWN) begin
            $display("[TB]   SKIP  scenario '%s' has no entry in expected_class()", scenario);
        end else begin
            if (last_cnn_class == expect_c)
                $display("[TB]   PASS  CNN class %s matches scenario", class_name(last_cnn_class));
            else begin
                $display("[TB]   FAIL  CNN class %s, expected %s",
                         class_name(last_cnn_class), class_name(expect_c));
                class_failures++;
            end
            if (last_mlp_class == expect_c)
                $display("[TB]   PASS  MLP class %s matches scenario", class_name(last_mlp_class));
            else begin
                $display("[TB]   %s  MLP class %s, expected %s%s",
                         aux_complete() ? "FAIL" : "INFO",
                         class_name(last_mlp_class), class_name(expect_c),
                         aux_complete() ? "" : " (aux captures missing -- see AUX_NOTE)");
                if (aux_complete()) class_failures++;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------
    initial begin
        read_config();
        $display("========================================================");
        $display(" tb_top_system");
        $display("   mode      = %s", mode);
        $display("   scenario  = %s", scenario);
        $display("   data_root = %s", data_root);
        $display("   clk       = %0d Hz, baud = %0d", CLK_FREQ_HZ, BAUD_RATE);
        $display("========================================================");

        apply_reset(32);

        if (mode == "uart")        run_uart_test();
        else if (mode == "stream") run_stream_test();
        else $fatal(1, "[TB] unknown MODE '%s' (use uart|stream)", mode);

        $display("========================================================");
        $display(" frames sent      : %0d", frames_sent);
        $display(" MLP verdicts     : %0d", mlp_results);
        $display(" CNN verdicts     : %0d", cnn_results);
        $display(" error_status     : %b", error_status);
        $display(" status_leds      : %b   alert_flag: %b   fault_mask: %b",
                 status_leds, alert_flag, sensor_fault_mask);
        $display(" health failures  : %0d", health_failures);
        $display(" class  failures  : %0d%s", class_failures,
                 strict_class ? " (strict: counted)" : " (informational)");
        if (health_failures == 0 && (!strict_class || class_failures == 0))
            $display(" RESULT: PASS");
        else
            $display(" RESULT: FAIL");
        $display("========================================================");

        for (int i = 0; i < N_SENSORS; i++) if (fd[i] != 0) $fclose(fd[i]);

        if (health_failures != 0 || (strict_class && class_failures != 0))
            $fatal(1, "[TB] test failed");
        $finish;
    end

    // Wall-clock safety net, generous enough for the full soak
    initial begin
        #(TIMEOUT_NS);
        $display("[TB] FAIL  global timeout at %0t, %0d frames sent", $time, frames_sent);
        $fatal(1, "[TB] timeout");
    end

endmodule
