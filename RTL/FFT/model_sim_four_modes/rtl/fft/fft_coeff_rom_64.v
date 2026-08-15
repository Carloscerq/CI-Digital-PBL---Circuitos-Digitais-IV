module fft_twiddle_rom_64 (
    input  wire [4:0] address,
    output reg signed [17:0] twiddle_real,
    output reg signed [17:0] twiddle_imag
);
    always @(*) begin
        twiddle_real = 18'sd0;
        twiddle_imag = 18'sd0;

        case (address)
            5'd0:  begin twiddle_real =  18'sd131071; twiddle_imag =  18'sd0;      end
            5'd1:  begin twiddle_real =  18'sd130441; twiddle_imag = -18'sd12847;  end
            5'd2:  begin twiddle_real =  18'sd128553; twiddle_imag = -18'sd25571;  end
            5'd3:  begin twiddle_real =  18'sd125428; twiddle_imag = -18'sd38048;  end
            5'd4:  begin twiddle_real =  18'sd121095; twiddle_imag = -18'sd50159;  end
            5'd5:  begin twiddle_real =  18'sd115595; twiddle_imag = -18'sd61787;  end
            5'd6:  begin twiddle_real =  18'sd108982; twiddle_imag = -18'sd72820;  end
            5'd7:  begin twiddle_real =  18'sd101320; twiddle_imag = -18'sd83151;  end
            5'd8:  begin twiddle_real =  18'sd92682;  twiddle_imag = -18'sd92682;  end
            5'd9:  begin twiddle_real =  18'sd83151;  twiddle_imag = -18'sd101320; end
            5'd10: begin twiddle_real =  18'sd72820;  twiddle_imag = -18'sd108982; end
            5'd11: begin twiddle_real =  18'sd61787;  twiddle_imag = -18'sd115595; end
            5'd12: begin twiddle_real =  18'sd50159;  twiddle_imag = -18'sd121095; end
            5'd13: begin twiddle_real =  18'sd38048;  twiddle_imag = -18'sd125428; end
            5'd14: begin twiddle_real =  18'sd25571;  twiddle_imag = -18'sd128553; end
            5'd15: begin twiddle_real =  18'sd12847;  twiddle_imag = -18'sd130441; end
            5'd16: begin twiddle_real =  18'sd0;      twiddle_imag =  18'sh20000;  end
            5'd17: begin twiddle_real = -18'sd12847;  twiddle_imag = -18'sd130441; end
            5'd18: begin twiddle_real = -18'sd25571;  twiddle_imag = -18'sd128553; end
            5'd19: begin twiddle_real = -18'sd38048;  twiddle_imag = -18'sd125428; end
            5'd20: begin twiddle_real = -18'sd50159;  twiddle_imag = -18'sd121095; end
            5'd21: begin twiddle_real = -18'sd61787;  twiddle_imag = -18'sd115595; end
            5'd22: begin twiddle_real = -18'sd72820;  twiddle_imag = -18'sd108982; end
            5'd23: begin twiddle_real = -18'sd83151;  twiddle_imag = -18'sd101320; end
            5'd24: begin twiddle_real = -18'sd92682;  twiddle_imag = -18'sd92682;  end
            5'd25: begin twiddle_real = -18'sd101320; twiddle_imag = -18'sd83151;  end
            5'd26: begin twiddle_real = -18'sd108982; twiddle_imag = -18'sd72820;  end
            5'd27: begin twiddle_real = -18'sd115595; twiddle_imag = -18'sd61787;  end
            5'd28: begin twiddle_real = -18'sd121095; twiddle_imag = -18'sd50159;  end
            5'd29: begin twiddle_real = -18'sd125428; twiddle_imag = -18'sd38048;  end
            5'd30: begin twiddle_real = -18'sd128553; twiddle_imag = -18'sd25571;  end
            5'd31: begin twiddle_real = -18'sd130441; twiddle_imag = -18'sd12847;  end

            default: begin
                twiddle_real = 18'sd0;
                twiddle_imag = 18'sd0;
            end
        endcase
    end
endmodule


module hann_rom_64 (
    input  wire [5:0] address,
    output reg signed [17:0] hann_coeff
);
    always @(*) begin
        case (address)
            6'd0:  hann_coeff = 18'sd0;
            6'd1:  hann_coeff = 18'sd326;
            6'd2:  hann_coeff = 18'sd1299;
            6'd3:  hann_coeff = 18'sd2912;
            6'd4:  hann_coeff = 18'sd5146;
            6'd5:  hann_coeff = 18'sd7981;
            6'd6:  hann_coeff = 18'sd11388;
            6'd7:  hann_coeff = 18'sd15333;
            6'd8:  hann_coeff = 18'sd19776;
            6'd9:  hann_coeff = 18'sd24675;
            6'd10: hann_coeff = 18'sd29980;
            6'd11: hann_coeff = 18'sd35638;
            6'd12: hann_coeff = 18'sd41593;
            6'd13: hann_coeff = 18'sd47786;
            6'd14: hann_coeff = 18'sd54156;
            6'd15: hann_coeff = 18'sd60638;
            6'd16: hann_coeff = 18'sd67170;
            6'd17: hann_coeff = 18'sd73685;
            6'd18: hann_coeff = 18'sd80119;
            6'd19: hann_coeff = 18'sd86408;
            6'd20: hann_coeff = 18'sd92490;
            6'd21: hann_coeff = 18'sd98304;
            6'd22: hann_coeff = 18'sd103792;
            6'd23: hann_coeff = 18'sd108900;
            6'd24: hann_coeff = 18'sd113577;
            6'd25: hann_coeff = 18'sd117777;
            6'd26: hann_coeff = 18'sd121457;
            6'd27: hann_coeff = 18'sd124582;
            6'd28: hann_coeff = 18'sd127120;
            6'd29: hann_coeff = 18'sd129045;
            6'd30: hann_coeff = 18'sd130340;
            6'd31: hann_coeff = 18'sd130991;
            6'd32: hann_coeff = 18'sd130991;
            6'd33: hann_coeff = 18'sd130340;
            6'd34: hann_coeff = 18'sd129045;
            6'd35: hann_coeff = 18'sd127120;
            6'd36: hann_coeff = 18'sd124582;
            6'd37: hann_coeff = 18'sd121457;
            6'd38: hann_coeff = 18'sd117777;
            6'd39: hann_coeff = 18'sd113577;
            6'd40: hann_coeff = 18'sd108900;
            6'd41: hann_coeff = 18'sd103792;
            6'd42: hann_coeff = 18'sd98304;
            6'd43: hann_coeff = 18'sd92490;
            6'd44: hann_coeff = 18'sd86408;
            6'd45: hann_coeff = 18'sd80119;
            6'd46: hann_coeff = 18'sd73685;
            6'd47: hann_coeff = 18'sd67170;
            6'd48: hann_coeff = 18'sd60638;
            6'd49: hann_coeff = 18'sd54156;
            6'd50: hann_coeff = 18'sd47786;
            6'd51: hann_coeff = 18'sd41593;
            6'd52: hann_coeff = 18'sd35638;
            6'd53: hann_coeff = 18'sd29980;
            6'd54: hann_coeff = 18'sd24675;
            6'd55: hann_coeff = 18'sd19776;
            6'd56: hann_coeff = 18'sd15333;
            6'd57: hann_coeff = 18'sd11388;
            6'd58: hann_coeff = 18'sd7981;
            6'd59: hann_coeff = 18'sd5146;
            6'd60: hann_coeff = 18'sd2912;
            6'd61: hann_coeff = 18'sd1299;
            6'd62: hann_coeff = 18'sd326;
            6'd63: hann_coeff = 18'sd0;
            default: hann_coeff = 18'sd0;
        endcase
    end
endmodule