// ---------------------------------------------------------------------
//  mlp_directed_seq  --  the same 7 fixed cases as randomise_features()
//                         in mlp_tb_dpi.sv: silence, tiny, saturating
//                         positive, saturating negative, one-hot bin 7,
//                         negative in the last bin, aggregates-only.
//                         Constants copied verbatim from that task.
//
//  mlp_random_seq  --  reproduces randomise_features()'s `default`
//                       branch: a magnitude drawn per vector (1-in-8
//                       pushed to the top of the ACC_WIDTH bus so the
//                       saturation path keeps being exercised), 1-3
//                       random peaks pushed into random bins, and the
//                       4 trailing aggregate features drawn from the
//                       ranges the notebook printed for the hardware
//                       bus (temperatures ~190-275, current power
//                       ~70-130, mdc_k0 0-64). `num_txns` is public so
//                       a test can crank the sweep up, mirroring
//                       perceptron_random_seq.
// ---------------------------------------------------------------------
class mlp_directed_seq extends uvm_sequence #(mlp_seq_item);

    `uvm_object_utils(mlp_directed_seq)

    function new(string name = "mlp_directed_seq");
        super.new(name);
    endfunction

    task body();
        mlp_seq_item item;
        logic signed [ACC_WIDTH-1:0] maxpos, maxneg;

        maxpos = (ACC_WIDTH'(1) <<< (ACC_WIDTH-1)) - 1'sb1;
        maxneg = -(ACC_WIDTH'(1) <<< (ACC_WIDTH-1));

        // 0: silence
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = '0;
        start_item(item); finish_item(item);

        // 1: tiny
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = ACC_WIDTH'(1);
        start_item(item); finish_item(item);

        // 2: saturating positive
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = maxpos;
        start_item(item); finish_item(item);

        // 3: saturating negative
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = maxneg;
        start_item(item); finish_item(item);

        // 4: one-hot bin 7
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = '0;
        item.features[7] = ACC_WIDTH'(50000);
        start_item(item); finish_item(item);

        // 5: negative in the last bin
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = '0;
        item.features[N_BINS-1] = -ACC_WIDTH'(50000);
        start_item(item); finish_item(item);

        // 6: aggregates only
        item = mlp_seq_item::type_id::create("item");
        foreach (item.features[i]) item.features[i] = '0;
        for (int i = N_BINS; i < N_IN; i++) item.features[i] = ACC_WIDTH'(255);
        start_item(item); finish_item(item);
    endtask

endclass

class mlp_random_seq extends uvm_sequence #(mlp_seq_item);

    `uvm_object_utils(mlp_random_seq)

    int unsigned num_txns = 300;

    function new(string name = "mlp_random_seq");
        super.new(name);
    endfunction

    task body();
        mlp_seq_item item;
        int mag, peaks, maxpos, hi_mag_clip;

        maxpos = (1 << (ACC_WIDTH-1)) - 1;

        repeat (num_txns) begin
            item = mlp_seq_item::type_id::create("item");

            // one vector in eight is pushed to the top of the ACC_WIDTH bus
            // so the saturation path keeps being exercised, mirroring
            // randomise_features()'s default branch in mlp_tb_dpi.sv
            mag = 1 << (($urandom_range(0, 7) == 0) ? $urandom_range(12, 22) : $urandom_range(4, 11));

            for (int i = 0; i < N_BINS; i++)
                item.features[i] = ACC_WIDTH'($urandom_range(0, mag)) - ACC_WIDTH'(mag/4);

            peaks       = $urandom_range(1, 3);
            hi_mag_clip = (mag * 8 > maxpos) ? maxpos : mag * 8;
            for (int p = 0; p < peaks; p++)
                item.features[$urandom_range(0, N_BINS-1)] =
                    ACC_WIDTH'($urandom_range(mag, hi_mag_clip));

            item.features[N_BINS+0] = ACC_WIDTH'($urandom_range(190, 275));  // Temperature_housing_A
            item.features[N_BINS+1] = ACC_WIDTH'($urandom_range(190, 275));  // Temperature_housing_B
            item.features[N_BINS+2] = ACC_WIDTH'($urandom_range( 70, 130));  // U-phase_pow
            item.features[N_BINS+3] = ACC_WIDTH'($urandom_range(  0,  64));  // mdc_k0

            start_item(item);
            finish_item(item);
        end
    endtask

endclass
