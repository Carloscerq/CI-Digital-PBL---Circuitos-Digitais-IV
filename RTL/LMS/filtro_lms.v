`timescale 1ns/1ps

module filtro_lms
#(
    parameter signed [23:0] MU = 24'sd1638
)
(
    input  wire                   clk,
    input  wire                   reset,

    input  wire                   in_valid,

    input  wire signed [23:0]     fft_re,
    input  wire signed [23:0]     fft_im,

    output wire                   in_ready,

    output reg signed [23:0]      filt_re,
    output reg signed [23:0]      filt_im,

    output wire                   out_valid
);


localparam      IDLE        = 4'b0000,
                RECEBE      = 4'b0001,
                MULT_Y      = 4'b0010,
                CALC_Y      = 4'b0011,
                CALC_ERRO   = 4'b0100,
                MULT_GRAD   = 4'b0101,
                CALC_GRAD   = 4'b0110,
                MULT_MU     = 4'b0111,
                ATUALIZA    = 4'b1000,
                ENVIA       = 4'b1001,
                FINALIZA    = 4'b1010,
                ERRO        = 4'b1111;



reg [3:0] estado_atual, proximo_estado;


reg primeira_amostra;


reg signed [23:0] d_re;
reg signed [23:0] d_im;


reg signed [23:0] x_prev_re;
reg signed [23:0] x_prev_im;


reg signed [23:0] w_re;
reg signed [23:0] w_im;


reg signed [23:0] y_re;
reg signed [23:0] y_im;


reg signed [23:0] e_re;
reg signed [23:0] e_im;


reg signed [23:0] grad_re;
reg signed [23:0] grad_im;


reg signed [47:0] mult1;
reg signed [47:0] mult2;
reg signed [47:0] mult3;
reg signed [47:0] mult4;


reg signed [47:0] mult_mu_re;
reg signed [47:0] mult_mu_im;



reg signed [48:0] temp49_re;
reg signed [48:0] temp49_im;

reg signed [48:0] scaled_re;
reg signed [48:0] scaled_im;

reg signed [24:0] temp25_re;
reg signed [24:0] temp25_im;

reg signed [23:0] delta_w_re;
reg signed [23:0] delta_w_im;



assign in_ready  = (estado_atual == IDLE);

assign out_valid = (estado_atual == ENVIA);



always @(posedge clk)
begin

    if (reset)
    begin

        estado_atual <= IDLE;

    end

    else
    begin

        estado_atual <= proximo_estado;

    end

end


always @(*)
begin

    proximo_estado = estado_atual;


    case (estado_atual)


        IDLE:
        begin

            if (in_valid)
            begin

                proximo_estado = RECEBE;

            end

            else
            begin

                proximo_estado = IDLE;

            end

        end


        RECEBE:
        begin

            if (primeira_amostra)
            begin

                proximo_estado = FINALIZA;

            end

            else
            begin

                proximo_estado = MULT_Y;

            end

        end


        MULT_Y:
        begin

            proximo_estado = CALC_Y;

        end


        CALC_Y:
        begin

            proximo_estado = CALC_ERRO;

        end


        CALC_ERRO:
        begin

            proximo_estado = MULT_GRAD;

        end


        MULT_GRAD:
        begin

            proximo_estado = CALC_GRAD;

        end


        CALC_GRAD:
        begin

            proximo_estado = MULT_MU;

        end


        MULT_MU:
        begin

            proximo_estado = ATUALIZA;

        end


        ATUALIZA:
        begin

            proximo_estado = ENVIA;

        end



        ENVIA:
        begin

            proximo_estado = FINALIZA;

        end


        FINALIZA:
        begin

            proximo_estado = IDLE;

        end


        ERRO:
        begin

            proximo_estado = IDLE;

        end

        default:
        begin

            proximo_estado = ERRO;

        end


    endcase

end



always @(posedge clk)
begin


    if (reset)
    begin

        primeira_amostra <= 1'b1;


        d_re <= 24'sd0;
        d_im <= 24'sd0;


        x_prev_re <= 24'sd0;
        x_prev_im <= 24'sd0;


        w_re <= 24'sd0;
        w_im <= 24'sd0;


        y_re <= 24'sd0;
        y_im <= 24'sd0;



        e_re <= 24'sd0;
        e_im <= 24'sd0;


        grad_re <= 24'sd0;
        grad_im <= 24'sd0;



        mult1 <= 48'sd0;
        mult2 <= 48'sd0;
        mult3 <= 48'sd0;
        mult4 <= 48'sd0;



        mult_mu_re <= 48'sd0;
        mult_mu_im <= 48'sd0;



        temp49_re <= 49'sd0;
        temp49_im <= 49'sd0;

        scaled_re <= 49'sd0;
        scaled_im <= 49'sd0;

        temp25_re <= 25'sd0;
        temp25_im <= 25'sd0;

        delta_w_re <= 24'sd0;
        delta_w_im <= 24'sd0;


        filt_re <= 24'sd0;
        filt_im <= 24'sd0;

    end


    else
    begin

        case (estado_atual)


            IDLE:
            begin

                if (in_valid)
                begin

                    d_re <= fft_re;
                    d_im <= fft_im;

                end

            end


            RECEBE:
            begin

                if (primeira_amostra)
                begin

                    x_prev_re <= d_re;
                    x_prev_im <= d_im;

                    primeira_amostra <= 1'b0;

                end

            end


            MULT_Y:
            begin

                mult1 <= w_re * x_prev_re;

                mult2 <= w_im * x_prev_im;

                mult3 <= w_re * x_prev_im;

                mult4 <= w_im * x_prev_re;

            end



            CALC_Y:
            begin



                temp49_re =
                    {mult1[47], mult1}
                    -
                    {mult2[47], mult2};




                temp49_im =
                    {mult3[47], mult3}
                    +
                    {mult4[47], mult4};



                scaled_re = temp49_re >>> 15;

                scaled_im = temp49_im >>> 15;



                if (scaled_re > 49'sd8388607)
                begin

                    y_re <= 24'sh7FFFFF;

                end

                else if (scaled_re < -49'sd8388608)
                begin

                    y_re <= 24'sh800000;

                end

                else
                begin

                    y_re <= scaled_re[23:0];

                end



                if (scaled_im > 49'sd8388607)
                begin

                    y_im <= 24'sh7FFFFF;

                end

                else if (scaled_im < -49'sd8388608)
                begin

                    y_im <= 24'sh800000;

                end

                else
                begin

                    y_im <= scaled_im[23:0];

                end

            end



            CALC_ERRO:
            begin

                temp25_re =
                    {d_re[23], d_re}
                    -
                    {y_re[23], y_re};


                temp25_im =
                    {d_im[23], d_im}
                    -
                    {y_im[23], y_im};



                if (temp25_re > 25'sd8388607)
                begin

                    e_re <= 24'sh7FFFFF;

                end

                else if (temp25_re < -25'sd8388608)
                begin

                    e_re <= 24'sh800000;

                end

                else
                begin

                    e_re <= temp25_re[23:0];

                end


                if (temp25_im > 25'sd8388607)
                begin

                    e_im <= 24'sh7FFFFF;

                end

                else if (temp25_im < -25'sd8388608)
                begin

                    e_im <= 24'sh800000;

                end

                else
                begin

                    e_im <= temp25_im[23:0];

                end

            end


            MULT_GRAD:
            begin

                mult1 <= e_re * x_prev_re;

                mult2 <= e_im * x_prev_im;

                mult3 <= e_im * x_prev_re;

                mult4 <= e_re * x_prev_im;

            end



            CALC_GRAD:
            begin


                temp49_re =
                    {mult1[47], mult1}
                    +
                    {mult2[47], mult2};


                temp49_im =
                    {mult3[47], mult3}
                    -
                    {mult4[47], mult4};



                scaled_re = temp49_re >>> 15;

                scaled_im = temp49_im >>> 15;


                if (scaled_re > 49'sd8388607)
                begin

                    grad_re <= 24'sh7FFFFF;

                end

                else if (scaled_re < -49'sd8388608)
                begin

                    grad_re <= 24'sh800000;

                end

                else
                begin

                    grad_re <= scaled_re[23:0];

                end



                if (scaled_im > 49'sd8388607)
                begin

                    grad_im <= 24'sh7FFFFF;

                end

                else if (scaled_im < -49'sd8388608)
                begin

                    grad_im <= 24'sh800000;

                end

                else
                begin

                    grad_im <= scaled_im[23:0];

                end

            end



            MULT_MU:
            begin

                mult_mu_re <= MU * grad_re;

                mult_mu_im <= MU * grad_im;

            end


            ATUALIZA:
            begin


                temp49_re =
                    {mult_mu_re[47], mult_mu_re};


                temp49_im =
                    {mult_mu_im[47], mult_mu_im};


                scaled_re = temp49_re >>> 15;

                scaled_im = temp49_im >>> 15;



                if (scaled_re > 49'sd8388607)
                begin

                    delta_w_re = 24'sh7FFFFF;

                end

                else if (scaled_re < -49'sd8388608)
                begin

                    delta_w_re = 24'sh800000;

                end

                else
                begin

                    delta_w_re = scaled_re[23:0];

                end



                if (scaled_im > 49'sd8388607)
                begin

                    delta_w_im = 24'sh7FFFFF;

                end

                else if (scaled_im < -49'sd8388608)
                begin

                    delta_w_im = 24'sh800000;

                end

                else
                begin

                    delta_w_im = scaled_im[23:0];

                end



                temp25_re =
                    {w_re[23], w_re}
                    +
                    {delta_w_re[23], delta_w_re};


                temp25_im =
                    {w_im[23], w_im}
                    +
                    {delta_w_im[23], delta_w_im};



                if (temp25_re > 25'sd8388607)
                begin

                    w_re <= 24'sh7FFFFF;

                end

                else if (temp25_re < -25'sd8388608)
                begin

                    w_re <= 24'sh800000;

                end

                else
                begin

                    w_re <= temp25_re[23:0];

                end


                if (temp25_im > 25'sd8388607)
                begin

                    w_im <= 24'sh7FFFFF;

                end

                else if (temp25_im < -25'sd8388608)
                begin

                    w_im <= 24'sh800000;

                end

                else
                begin

                    w_im <= temp25_im[23:0];

                end


                x_prev_re <= d_re;

                x_prev_im <= d_im;


                filt_re <= y_re;

                filt_im <= y_im;

            end


            ENVIA:
            begin

            end

            FINALIZA:
            begin

            end

            ERRO:
            begin

            end

            default:
            begin

            end


        endcase

    end

end


endmodule
