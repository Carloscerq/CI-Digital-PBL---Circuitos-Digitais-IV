// ---------------------------------------------------------------------
//  filtro_lms_directed_seq  --  reproduces tb_filtro_lms.v's 20-sample
//                                bin sequence verbatim, as a regression
//                                pin: same fft_re/fft_im pairs, same
//                                order.
//
//  filtro_lms_random_seq        -- constrained-random samples bounded to
//                                   a moderate magnitude, in the same
//                                   rough range as the directed values
//                                   (tens of thousands to a few hundred
//                                   thousand). This is the sequence that
//                                   actually stress-tests the adaptive
//                                   tracking behavior: the deep
//                                   multiply-chain (Q15 complex multiply
//                                   -> Q15 complex multiply -> Q15 MU
//                                   scale -> add) saturates on step 1
//                                   almost every time given unbounded
//                                   full-24-bit-range inputs, which
//                                   mostly just exercises saturation
//                                   clamps rather than the LMS math.
//
//  filtro_lms_wide_random_seq   -- unconstrained full-24-bit-range random
//                                   samples, deliberately chosen to hit
//                                   saturation at every stage of the
//                                   pipeline, complementing the moderate-
//                                   magnitude sequence above.
// ---------------------------------------------------------------------
class filtro_lms_directed_seq extends uvm_sequence #(filtro_lms_seq_item);

    `uvm_object_utils(filtro_lms_directed_seq)

    function new(string name = "filtro_lms_directed_seq");
        super.new(name);
    endfunction

    task body();
        send(24'sd72090, 24'sd36045); // bin 1
        send(24'sd58982, 24'sd29491); // bin 2
        send(24'sd68813, 24'sd34406); // bin 3
        send(24'sd62259, 24'sd31130); // bin 4
        send(24'sd67174, 24'sd33751); // bin 5
        send(24'sd63898, 24'sd32113); // bin 6
        send(24'sd68157, 24'sd34079); // bin 7
        send(24'sd62915, 24'sd31457); // bin 8
        send(24'sd66518, 24'sd33259); // bin 9
        send(24'sd64226, 24'sd32113); // bin 10
        send(24'sd65863, 24'sd32932); // bin 11
        send(24'sd64881, 24'sd32440); // bin 12
        send(24'sd66191, 24'sd33095); // bin 13
        send(24'sd64553, 24'sd32276); // bin 14
        send(24'sd65536, 24'sd32768); // bin 15
        send(24'sd65208, 24'sd32604); // bin 16
        send(24'sd65863, 24'sd32932); // bin 17
        send(24'sd64881, 24'sd32440); // bin 18
        send(24'sd65536, 24'sd32768); // bin 19
        send(24'sd65536, 24'sd32768); // bin 20
    endtask

    task send(logic signed [23:0] re, logic signed [23:0] im);
        filtro_lms_seq_item item;
        item = filtro_lms_seq_item::type_id::create("item");
        start_item(item);
        item.fft_re = re;
        item.fft_im = im;
        finish_item(item);
    endtask

endclass

class filtro_lms_random_seq extends uvm_sequence #(filtro_lms_seq_item);

    `uvm_object_utils(filtro_lms_random_seq)

    int unsigned num_samples = 30;

    function new(string name = "filtro_lms_random_seq");
        super.new(name);
    endfunction

    task body();
        filtro_lms_seq_item item;
        repeat (num_samples) begin
            item = filtro_lms_seq_item::type_id::create("item");
            start_item(item);
            if (!item.randomize() with {
                    fft_re inside {[-24'sd300000:24'sd300000]};
                    fft_im inside {[-24'sd300000:24'sd300000]};
                })
                `uvm_error("RAND", "moderate-magnitude randomize failed")
            finish_item(item);
        end
    endtask

endclass

class filtro_lms_wide_random_seq extends uvm_sequence #(filtro_lms_seq_item);

    `uvm_object_utils(filtro_lms_wide_random_seq)

    int unsigned num_samples = 20;

    function new(string name = "filtro_lms_wide_random_seq");
        super.new(name);
    endfunction

    task body();
        filtro_lms_seq_item item;
        repeat (num_samples) begin
            item = filtro_lms_seq_item::type_id::create("item");
            start_item(item);
            if (!item.randomize())
                `uvm_error("RAND", "wide-range randomize failed")
            finish_item(item);
        end
    endtask

endclass
