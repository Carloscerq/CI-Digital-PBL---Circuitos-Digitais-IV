// ---------------------------------------------------------------------
//  mac_q8_16_directed_seq  --  the four hand-checkable jobs from
//                     tb_mac_q8_16.sv, reproduced with the exact same
//                     Q8.16 hex literals so the expected results are
//                     traceable back to that reference testbench:
//                       1) 1.5 * 2.0        =  3.0   (pos * pos)
//                       2) 2.0 * -0.5       = -1.0   (pos * neg)
//                       3) -1.5 * -2.0      =  3.0   (neg * neg)
//                       4) 0.5*2.0 + 1.5*-1.0 + 0.5*0.5 = -0.25
//                          (3-tap pipelined accumulation)
//
//  mac_q8_16_sat_seq  --  MAX_TAPS taps at the widest DATA_WIDTH
//                     magnitude, both signs, to drive the accumulator
//                     into overflow and underflow saturation -- the
//                     behavior mac_q8_16.sv's always_comb block exists
//                     to handle and tb_mac_q8_16.sv does not itself
//                     cover.
//
//  mac_q8_16_random_seq  --  constrained-random jobs swept across a
//                     handful of tap-count sizes, including magnitudes
//                     large enough to sometimes saturate, so the
//                     scoreboard's normal/overflow/underflow coverage
//                     gets exercised without everything being hand-picked.
// ---------------------------------------------------------------------
class mac_q8_16_directed_seq #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_sequence #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS));

    `uvm_object_param_utils(mac_q8_16_directed_seq #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    function new(string name = "mac_q8_16_directed_seq");
        super.new(name);
    endfunction

    task body();
        logic signed [DATA_WIDTH-1:0] a1[], b1[];
        logic signed [DATA_WIDTH-1:0] a2[], b2[];
        logic signed [DATA_WIDTH-1:0] a3[], b3[];
        logic signed [DATA_WIDTH-1:0] a4[], b4[];

        // 1) Pos * Pos: 1.5 * 2.0 = 3.0
        a1 = new[1]; b1 = new[1];
        a1[0] = 24'h01_8000; b1[0] = 24'h02_0000;
        send_job(a1, b1);

        // 2) Pos * Neg: 2.0 * -0.5 = -1.0
        a2 = new[1]; b2 = new[1];
        a2[0] = 24'h02_0000; b2[0] = 24'hFF_8000;
        send_job(a2, b2);

        // 3) Neg * Neg: -1.5 * -2.0 = 3.0
        a3 = new[1]; b3 = new[1];
        a3[0] = 24'hFE_8000; b3[0] = 24'hFE_0000;
        send_job(a3, b3);

        // 4) 3-tap pipelined accumulation: 1.0 - 1.5 + 0.25 = -0.25
        a4 = new[3]; b4 = new[3];
        a4[0] = 24'h00_8000; b4[0] = 24'h02_0000;
        a4[1] = 24'h01_8000; b4[1] = 24'hFF_0000;
        a4[2] = 24'h00_8000; b4[2] = 24'h00_8000;
        send_job(a4, b4);
    endtask

    task send_job(logic signed [DATA_WIDTH-1:0] a[], logic signed [DATA_WIDTH-1:0] b[]);
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) item;
        item = mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("item");
        start_item(item);
        item.n_taps = a.size();
        item.a      = a;
        item.b      = b;
        finish_item(item);
    endtask

endclass

class mac_q8_16_sat_seq #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_sequence #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS));

    `uvm_object_param_utils(mac_q8_16_sat_seq #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    function new(string name = "mac_q8_16_sat_seq");
        super.new(name);
    endfunction

    task body();
        // most negative a * most negative b, MAX_TAPS times -> drives the
        // accumulator into positive (overflow) saturation
        send_uniform(-(longint'(1) <<< (DATA_WIDTH-1)), -(longint'(1) <<< (DATA_WIDTH-1)));

        // most positive a * most negative b, MAX_TAPS times -> drives the
        // accumulator into negative (underflow) saturation
        send_uniform((longint'(1) <<< (DATA_WIDTH-1)) - 1, -(longint'(1) <<< (DATA_WIDTH-1)));
    endtask

    task send_uniform(longint signed aval, longint signed bval);
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) item;
        item = mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("item");
        start_item(item);
        item.n_taps = MAX_TAPS;
        item.a      = new[MAX_TAPS];
        item.b      = new[MAX_TAPS];
        foreach (item.a[i]) item.a[i] = DATA_WIDTH'(aval);
        foreach (item.b[i]) item.b[i] = DATA_WIDTH'(bval);
        finish_item(item);
    endtask

endclass

class mac_q8_16_random_seq #(
    int DATA_WIDTH = 24,
    int FRAC_BITS  = 16,
    int MAX_TAPS   = 64
) extends uvm_sequence #(mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS));

    `uvm_object_param_utils(mac_q8_16_random_seq #(DATA_WIDTH, FRAC_BITS, MAX_TAPS))

    int unsigned num_trials = 40;

    function new(string name = "mac_q8_16_random_seq");
        super.new(name);
    endfunction

    task body();
        int lengths[5] = '{1, 2, 4, 16, MAX_TAPS};
        mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS) item;

        foreach (lengths[k]) begin
            repeat (num_trials) begin
                item = mac_q8_16_seq_item #(DATA_WIDTH, FRAC_BITS, MAX_TAPS)::type_id::create("item");
                start_item(item);
                // wide enough magnitude range that some jobs saturate,
                // without every job saturating
                if (!item.randomize() with {
                        n_taps == lengths[k];
                        foreach (a[i]) a[i] inside {[-(24'sh10_0000):24'sh10_0000]};
                        foreach (b[i]) b[i] inside {[-(24'sh10_0000):24'sh10_0000]};
                    })
                    `uvm_error("RAND", "random item randomize failed")
                finish_item(item);
            end
        end
    endtask

endclass
