`timescale 1ns/1ps

module tb_filtro_lms;


reg clk;
reg reset;

reg in_valid;

reg signed [23:0] fft_re;
reg signed [23:0] fft_im;

wire in_ready;

wire signed [23:0] filt_re;
wire signed [23:0] filt_im;

wire out_valid;


filtro_lms
#(
    .MU(24'sd1638)
)
dut
(
    .clk        (clk),
    .reset      (reset),

    .in_valid   (in_valid),

    .fft_re     (fft_re),
    .fft_im     (fft_im),

    .in_ready   (in_ready),

    .filt_re    (filt_re),
    .filt_im    (filt_im),

    .out_valid  (out_valid)
);



initial
begin

    clk = 1'b0;
    forever #5 clk = ~clk;
end


always @(posedge clk)
begin

    if (out_valid)
    begin

        $display(
            "tempo = %0t | filtrado = (%0d , %0d)",
            $time,
            filt_re,
            filt_im
        );

    end

end


initial
begin

    reset = 1'b1;

    in_valid = 1'b0;

    fft_re = 24'sd0;

    fft_im = 24'sd0;

    #30;

    reset = 1'b0;

    #20;

//bin 1

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd72090;
    fft_im = 24'sd36045;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;

//bin 2

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd58982;
    fft_im = 24'sd29491;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;

//bin 3

    wait(out_valid == 1'b1);

    @(negedge clk);




    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd68813;
    fft_im = 24'sd34406;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 4

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd62259;
    fft_im = 24'sd31130;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);


//bin 5

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd67174;
    fft_im = 24'sd33751;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 6

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd63898;
    fft_im = 24'sd32113;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 7

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd68157;
    fft_im = 24'sd34079;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 8

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd62915;
    fft_im = 24'sd31457;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 9

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd66518;
    fft_im = 24'sd33259;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 10

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd64226;
    fft_im = 24'sd32113;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 11

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd65863;
    fft_im = 24'sd32932;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 12

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd64881;
    fft_im = 24'sd32440;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 13

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd66191;
    fft_im = 24'sd33095;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 14

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd64553;
    fft_im = 24'sd32276;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

//bin 15

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd65536;
    fft_im = 24'sd32768;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);

    wait(in_ready == 1'b1);


    @(negedge clk);

//bin 16

    fft_re = 24'sd65208;
    fft_im = 24'sd32604;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);


//bin 17

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd65863;
    fft_im = 24'sd32932;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);


//bin 18

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd64881;
    fft_im = 24'sd32440;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);


//bin 19
    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd65536;
    fft_im = 24'sd32768;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);

    @(negedge clk);


//bin 20

    wait(in_ready == 1'b1);

    @(negedge clk);

    fft_re = 24'sd65536;
    fft_im = 24'sd32768;

    in_valid = 1'b1;

    @(negedge clk);

    in_valid = 1'b0;


    wait(out_valid == 1'b1);


    #100;

    $display("");
    $display("=======================================");
    $display("       FIM DA SIMULACAO");
    $display("=======================================");
    $display("");

    $stop;

end


endmodule
