// ---------------------------------------------------------------------
//  mac_directed_seq  --  the two hand-checkable jobs from mac_tb.sv:
//                         the -32 dot product (DIRECTED) and the
//                         ZERO_WEIGHTS check (weight=0 on all but one
//                         tap must not disturb the sum -- mlp.sv relies
//                         on exactly this to idle unused MACs).
//
//  mac_sat_seq       --  MAX_TAPS taps at the widest DATA_WIDTH/
//                         WEIGHT_WIDTH magnitudes, both signs, mirroring
//                         mac_tb.sv's SAT_MAX_POS/SAT_MAX_NEG checks.
//
//  mac_random_seq    --  constrained-random dot products swept across
//                         the same tap-count buckets {1,2,4,8,33,
//                         MAX_TAPS} mac_tb.sv exercises, so "short job"
//                         vs. "one full MAX_TAPS job" coverage isn't
//                         left to chance.
// ---------------------------------------------------------------------
class mac_directed_seq #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_sequence #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS));

    `uvm_object_param_utils(mac_directed_seq #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    function new(string name = "mac_directed_seq");
        super.new(name);
    endfunction

    task body();
        logic signed [DATA_WIDTH-1:0]   d3 [];
        logic signed [WEIGHT_WIDTH-1:0] w3 [];
        logic signed [DATA_WIDTH-1:0]   zd [];
        logic signed [WEIGHT_WIDTH-1:0] zw [];

        // 3*4 + (-5)*6 + 7*(-2) = 12 - 30 - 14 = -32 (mac_tb.sv's DIRECTED check)
        d3 = new[3]; w3 = new[3];
        d3[0] =  DATA_WIDTH'(3); w3[0] =  WEIGHT_WIDTH'(4);
        d3[1] = -DATA_WIDTH'(5); w3[1] =  WEIGHT_WIDTH'(6);
        d3[2] =  DATA_WIDTH'(7); w3[2] = -WEIGHT_WIDTH'(2);
        send_dot(d3, w3);

        // zero weights must not disturb the running sum (mlp.sv feeds
        // weight 0 to idle MACs during layers 1 and 2; mac_tb.sv's
        // ZERO_WEIGHTS check)
        zd = new[16]; zw = new[16];
        for (int i = 0; i < 16; i++) begin
            zd[i] = DATA_WIDTH'(123456);
            zw[i] = (i == 0) ? WEIGHT_WIDTH'(3) : WEIGHT_WIDTH'(0);
        end
        send_dot(zd, zw);
    endtask

    task send_dot(logic signed [DATA_WIDTH-1:0] d[], logic signed [WEIGHT_WIDTH-1:0] w[]);
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) item;
        item = mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("item");
        start_item(item);
        item.n_taps = d.size();
        item.data   = d;
        item.weight = w;
        finish_item(item);
    endtask

endclass

class mac_sat_seq #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_sequence #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS));

    `uvm_object_param_utils(mac_sat_seq #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    function new(string name = "mac_sat_seq");
        super.new(name);
    endfunction

    task body();
        // most negative data * most negative weight, MAX_TAPS times -> the
        // largest positive accumulation the widths allow (SAT_MAX_POS)
        send_uniform(-(longint'(1) <<< (DATA_WIDTH-1)), -(longint'(1) <<< (WEIGHT_WIDTH-1)));

        // most positive data * most negative weight, MAX_TAPS times -> the
        // largest negative accumulation the widths allow (SAT_MAX_NEG)
        send_uniform((longint'(1) <<< (DATA_WIDTH-1)) - 1, -(longint'(1) <<< (WEIGHT_WIDTH-1)));
    endtask

    task send_uniform(longint signed dval, longint signed wval);
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) item;
        item = mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("item");
        start_item(item);
        item.n_taps = MAX_TAPS;
        item.data   = new[MAX_TAPS];
        item.weight = new[MAX_TAPS];
        foreach (item.data[i])   item.data[i]   = DATA_WIDTH'(dval);
        foreach (item.weight[i]) item.weight[i] = WEIGHT_WIDTH'(wval);
        finish_item(item);
    endtask

endclass

class mac_random_seq #(
    int DATA_WIDTH   = 24,
    int WEIGHT_WIDTH = 8,
    int SUM_WIDTH    = 40,
    int MAX_TAPS     = 132
) extends uvm_sequence #(mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS));

    `uvm_object_param_utils(mac_random_seq #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS))

    int unsigned num_trials = 40;

    function new(string name = "mac_random_seq");
        super.new(name);
    endfunction

    task body();
        int lengths[6] = '{1, 2, 4, 8, 33, MAX_TAPS};
        mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS) item;

        foreach (lengths[k]) begin
            repeat (num_trials) begin
                item = mac_seq_item #(DATA_WIDTH, WEIGHT_WIDTH, SUM_WIDTH, MAX_TAPS)::type_id::create("item");
                start_item(item);
                if (!item.randomize() with { n_taps == lengths[k]; })
                    `uvm_error("RAND", "random item randomize failed")
                finish_item(item);
            end
        end
    endtask

endclass
