`timescale 1ns/1ps
// Model-specific combinational ROM. Layer IDs 0..4=conv1/2/3/fc1/2.
// Checkpoint f5d5b047773f9efc2af9e80945927eba7d4edd7c66e8a88ee3e4d6fcff82b407.
// Regenerate/review for a different checkpoint. No read latency.
module kws_pot_shift_rom(input logic [2:0] layer_id, input logic [4:0] channel_id,
                         output logic [4:0] shift_amount, output logic valid);
    always_comb begin
        shift_amount=0; valid=1;
        case ({layer_id,channel_id})
            8'd0: shift_amount=5'd8;
            8'd1: shift_amount=5'd9;
            8'd2: shift_amount=5'd9;
            8'd3: shift_amount=5'd9;
            8'd4: shift_amount=5'd8;
            8'd5: shift_amount=5'd9;
            8'd6: shift_amount=5'd9;
            8'd7: shift_amount=5'd9;
            8'd8: shift_amount=5'd9;
            8'd9: shift_amount=5'd9;
            8'd10: shift_amount=5'd8;
            8'd11: shift_amount=5'd9;
            8'd32: shift_amount=5'd9;
            8'd33: shift_amount=5'd8;
            8'd34: shift_amount=5'd8;
            8'd35: shift_amount=5'd8;
            8'd36: shift_amount=5'd7;
            8'd37: shift_amount=5'd8;
            8'd38: shift_amount=5'd7;
            8'd39: shift_amount=5'd8;
            8'd40: shift_amount=5'd8;
            8'd41: shift_amount=5'd8;
            8'd42: shift_amount=5'd8;
            8'd43: shift_amount=5'd8;
            8'd64: shift_amount=5'd8;
            8'd65: shift_amount=5'd8;
            8'd66: shift_amount=5'd8;
            8'd67: shift_amount=5'd8;
            8'd68: shift_amount=5'd8;
            8'd69: shift_amount=5'd8;
            8'd70: shift_amount=5'd8;
            8'd71: shift_amount=5'd10;
            8'd72: shift_amount=5'd9;
            8'd73: shift_amount=5'd8;
            8'd74: shift_amount=5'd8;
            8'd75: shift_amount=5'd8;
            8'd96: shift_amount=5'd7;
            8'd97: shift_amount=5'd7;
            8'd98: shift_amount=5'd7;
            8'd99: shift_amount=5'd7;
            8'd100: shift_amount=5'd7;
            8'd101: shift_amount=5'd7;
            8'd102: shift_amount=5'd7;
            8'd103: shift_amount=5'd7;
            8'd104: shift_amount=5'd7;
            8'd105: shift_amount=5'd7;
            8'd106: shift_amount=5'd8;
            8'd107: shift_amount=5'd7;
            8'd108: shift_amount=5'd7;
            8'd109: shift_amount=5'd8;
            8'd110: shift_amount=5'd7;
            8'd111: shift_amount=5'd7;
            8'd112: shift_amount=5'd7;
            8'd113: shift_amount=5'd7;
            8'd114: shift_amount=5'd7;
            8'd115: shift_amount=5'd7;
            8'd116: shift_amount=5'd7;
            8'd117: shift_amount=5'd7;
            8'd118: shift_amount=5'd7;
            8'd119: shift_amount=5'd8;
            8'd120: shift_amount=5'd7;
            8'd121: shift_amount=5'd7;
            8'd122: shift_amount=5'd7;
            8'd123: shift_amount=5'd8;
            8'd124: shift_amount=5'd8;
            8'd125: shift_amount=5'd7;
            8'd126: shift_amount=5'd7;
            8'd127: shift_amount=5'd7;
            8'd128: shift_amount=5'd6;
            8'd129: shift_amount=5'd6;
            8'd130: shift_amount=5'd6;
            8'd131: shift_amount=5'd6;
            8'd132: shift_amount=5'd6;
            8'd133: shift_amount=5'd6;
            8'd134: shift_amount=5'd6;
            8'd135: shift_amount=5'd6;
            default: begin shift_amount=0; valid=0; end
        endcase
    end
endmodule
