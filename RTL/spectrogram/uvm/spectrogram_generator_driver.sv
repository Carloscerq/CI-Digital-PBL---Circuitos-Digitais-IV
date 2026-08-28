// ---------------------------------------------------------------------
//  spectrogram_generator_driver  --  streams one frame's MEM_DEPTH
//  (1024) words onto the slave (FFT-in) AXI4-Stream side, honouring
//  s_axis_ready backpressure and asserting s_axis_last on the last
//  word, mirroring feed_fft_frames() in tb_spectrogram_generator.sv
//  exactly: s_axis_valid/s_axis_data/s_axis_last are set, the driver
//  waits a posedge and then keeps waiting full posedges while the DUT
//  stalls (s_axis_ready low), then drops valid/last for one cycle
//  before possibly inserting a randomized bursty gap
//  ($urandom_range(0,3)==0 triggers 1-3 idle cycles) to emulate FFT
//  delay and stress the ping-pong swap.
//
//  frame_ap publishes the whole frame (the same item just streamed) the
//  moment it starts driving, so the scoreboard can check the monitor's
//  observed output word for word against this ground truth without
//  trusting anything the DUT produces -- the same "driver publishes
//  ground truth on its own analysis port" shape line_buffer_3x3_driver.sv
//  uses.
// ---------------------------------------------------------------------
class spectrogram_generator_driver extends uvm_driver #(spectrogram_generator_seq_item);

    `uvm_component_utils(spectrogram_generator_driver)

    virtual spectrogram_generator_if vif;
    uvm_analysis_port #(spectrogram_generator_seq_item) frame_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        frame_ap = new("frame_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual spectrogram_generator_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for driver")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            frame_ap.write(req);   // publish ground truth before/while streaming it
            drive_frame(req);
            seq_item_port.item_done();
        end
    endtask

    task automatic drive_frame(spectrogram_generator_seq_item item);
        vif.s_axis_valid = 1'b0;
        vif.s_axis_last  = 1'b0;
        @(posedge vif.clk);

        for (int i = 0; i < MEM_DEPTH; i++) begin
            vif.s_axis_valid = 1'b1;
            vif.s_axis_data  = item.words[i];
            vif.s_axis_last  = (i == MEM_DEPTH - 1);

            @(posedge vif.clk);
            while (!vif.s_axis_ready) @(posedge vif.clk);

            vif.s_axis_valid = 1'b0;
            vif.s_axis_last  = 1'b0;

            // Emulate FFT delay (bursty writes) to stress the ping-pong
            // swap, mirroring feed_fft_frames()'s
            // $urandom_range(0,3)==0 -> repeat($urandom_range(1,3)) gap.
            if ($urandom_range(0, 3) == 0)
                repeat ($urandom_range(1, 3)) @(posedge vif.clk);
        end
    endtask

endclass
