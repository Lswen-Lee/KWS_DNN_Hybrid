`timescale 1ns/1ps
// Precomputed independent integer golden: sum((A-127)*signed(W)).
module pe_board_golden(input wire [1:0] test_id, input wire [4:0] channel_id,
                       output logic signed [31:0] value);
    always_comb begin
        value=0;
        case ({test_id,channel_id})
            7'd0: value=32'sd10524;
            7'd1: value=32'sd17886;
            7'd2: value=-32'sd12128;
            7'd3: value=-32'sd25758;
            7'd4: value=32'sd10276;
            7'd5: value=32'sd39654;
            7'd6: value=-32'sd22872;
            7'd7: value=-32'sd14486;
            7'd8: value=32'sd21036;
            7'd9: value=32'sd6894;
            7'd10: value=-32'sd22608;
            7'd11: value=32'sd7794;
            7'd32: value=-32'sd18712;
            7'd33: value=-32'sd44848;
            7'd34: value=-32'sd35144;
            7'd35: value=-32'sd17760;
            7'd36: value=32'sd30344;
            7'd37: value=32'sd20592;
            7'd38: value=32'sd22872;
            7'd39: value=32'sd28736;
            7'd40: value=-32'sd37336;
            7'd41: value=32'sd16;
            7'd42: value=32'sd43256;
            7'd43: value=32'sd24544;
            7'd44: value=32'sd5576;
            7'd45: value=32'sd5040;
            7'd46: value=-32'sd39784;
            7'd47: value=-32'sd65664;
            7'd48: value=-32'sd4504;
            7'd49: value=32'sd26704;
            7'd50: value=32'sd11576;
            7'd51: value=-32'sd45280;
            7'd52: value=32'sd2056;
            7'd53: value=-32'sd528;
            7'd54: value=32'sd29912;
            7'd55: value=32'sd22720;
            7'd56: value=32'sd25256;
            7'd57: value=32'sd28304;
            7'd58: value=-32'sd48264;
            7'd59: value=-32'sd23712;
            7'd60: value=32'sd30024;
            7'd61: value=32'sd24112;
            7'd62: value=-32'sd44264;
            7'd63: value=-32'sd21248;
            7'd64: value=-32'sd5840;
            7'd65: value=32'sd3040;
            7'd66: value=32'sd32144;
            7'd67: value=32'sd16704;
            7'd68: value=-32'sd20496;
            7'd69: value=-32'sd16736;
            7'd70: value=-32'sd8624;
            7'd71: value=32'sd20480;
            default: value=0;
        endcase
    end
endmodule
