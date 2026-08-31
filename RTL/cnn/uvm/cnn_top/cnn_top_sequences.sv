// ---------------------------------------------------------------------
//  cnn_top_directed_seq  --  loads the REAL spectrogram frame
//  tb_cnn_top.sv uses, Scripts/cnn/cnn_tb_input.mem (repo-root
//  relative; resolves correctly once run_uvm.sh has cd'd into RTL/, so
//  the relative path here, "../Scripts/cnn/cnn_tb_input.mem", is
//  identical to the literal path tb_cnn_top.sv itself uses), and
//  streams it through the whole 4-stage pipeline for one realistic
//  end-to-end run. Same raster-order/4-channel-interleaved flattening
//  tb_cnn_top.sv's own `tb_image_data[(i*4)+ch]` indexing uses,
//  just unflattened into pixels[r][c][ch] here (i = r*IMG_WIDTH + c).
//
//  cnn_top_random_seq  --  a small handful of frames (default 1)
//  with fully randomized pixel content, for basic additional coverage
//  beyond the one real-data frame. num_frames is public so a test can
//  adjust the sweep, mirroring line_buffer_3x3_random_seq/
//  mlp_random_seq. A full 1024-pixel frame through all 4 pipeline
//  stages is already a lot of simulated activity per item, so this is
//  kept deliberately small -- one directed + one random frame is the
//  whole default test.
// ---------------------------------------------------------------------
class cnn_top_directed_seq extends uvm_sequence #(cnn_top_seq_item);

    `uvm_object_utils(cnn_top_directed_seq)

    function new(string name = "cnn_top_directed_seq");
        super.new(name);
    endfunction

    task body();
        cnn_top_seq_item item;
        logic [DATA_WIDTH-1:0] tb_image_data [0:(NUM_PIXELS*IN_CHANNELS)-1];

        $readmemh("../Scripts/cnn/cnn_tb_input.mem", tb_image_data);

        item = cnn_top_seq_item::type_id::create("item");

        for (int r = 0; r < IMG_HEIGHT; r++) begin
            for (int c = 0; c < IMG_WIDTH; c++) begin
                automatic int idx = (r * IMG_WIDTH) + c;
                for (int ch = 0; ch < IN_CHANNELS; ch++) begin
                    item.pixels[r][c][ch] = tb_image_data[(idx * IN_CHANNELS) + ch];
                end
            end
        end

        start_item(item);
        finish_item(item);
    endtask

endclass

class cnn_top_random_seq extends uvm_sequence #(cnn_top_seq_item);

    `uvm_object_utils(cnn_top_random_seq)

    int unsigned num_frames = 1;

    function new(string name = "cnn_top_random_seq");
        super.new(name);
    endfunction

    task body();
        cnn_top_seq_item item;
        repeat (num_frames) begin
            item = cnn_top_seq_item::type_id::create("item");
            if (!item.randomize())
                `uvm_fatal("RAND", "failed to randomize cnn_top_seq_item frame")
            start_item(item);
            finish_item(item);
        end
    endtask

endclass
