`timescale 1ns/1ps
// Independent precomputed end-to-end board golden, zp128/PoT/ReLU, no bias.
module pe_board_golden_pot(input wire [1:0] test_id, input wire [4:0] channel_id,
    output logic signed [31:0] value);
    always_comb begin
        value=0;
        case({test_id,channel_id})
            7'd0: value=32'sd170;
            7'd1: value=32'sd163;
            7'd2: value=32'sd128;
            7'd3: value=32'sd128;
            7'd4: value=32'sd169;
            7'd5: value=32'sd205;
            7'd6: value=32'sd128;
            7'd7: value=32'sd128;
            7'd8: value=32'sd169;
            7'd9: value=32'sd141;
            7'd10: value=32'sd128;
            7'd11: value=32'sd143;
            7'd32: value=32'sd128;
            7'd33: value=32'sd128;
            7'd34: value=32'sd128;
            7'd35: value=32'sd128;
            7'd36: value=32'sd255;
            7'd37: value=32'sd255;
            7'd38: value=32'sd255;
            7'd39: value=32'sd255;
            7'd40: value=32'sd128;
            7'd41: value=32'sd129;
            7'd42: value=32'sd255;
            7'd43: value=32'sd255;
            7'd44: value=32'sd173;
            7'd45: value=32'sd148;
            7'd46: value=32'sd128;
            7'd47: value=32'sd128;
            7'd48: value=32'sd128;
            7'd49: value=32'sd255;
            7'd50: value=32'sd221;
            7'd51: value=32'sd128;
            7'd52: value=32'sd143;
            7'd53: value=32'sd128;
            7'd54: value=32'sd255;
            7'd55: value=32'sd217;
            7'd56: value=32'sd255;
            7'd57: value=32'sd255;
            7'd58: value=32'sd128;
            7'd59: value=32'sd128;
            7'd60: value=32'sd245;
            7'd61: value=32'sd255;
            7'd62: value=32'sd128;
            7'd63: value=32'sd128;
            7'd64: value=32'sd39;
            7'd65: value=32'sd170;
            7'd66: value=32'sd255;
            7'd67: value=32'sd255;
            7'd68: value=32'sd0;
            7'd69: value=32'sd0;
            7'd70: value=32'sd0;
            7'd71: value=32'sd255;
            default: value=0;
        endcase
    end
endmodule
