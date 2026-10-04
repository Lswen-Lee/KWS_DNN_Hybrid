`timescale 1ns/1ps
// Fixed model metadata, NOT weights or feature-map storage.
// Combinational lookup; layer_controller registers the selected descriptor.
module layer_descriptor_rom (
    input logic [3:0] op_index,
    output kws_system_pkg::layer_descriptor_t descriptor,
    output logic descriptor_valid
);
    import kws_system_pkg::*;
    always_comb begin
        descriptor = '0;
        descriptor_valid = 1'b1;
        // Order: kind, backend, weight/PoT ID, src, dst, W, H, Cin, Cout, K, ReLU.
        case (op_index)
            0: descriptor = '{OP_POOL, BACKEND_POOL, 3'd0, 15'd0, 15'd8064,
                              8'd126, 8'd64, 6'd1, 6'd1, 8'd0, 1'b0};
            1: descriptor = '{OP_CONV, BACKEND_PE, 3'd0, 15'd8064, 15'd10080,
                              8'd63, 8'd32, 6'd1, 6'd12, 8'd9, 1'b1};
            2: descriptor = '{OP_POOL, BACKEND_POOL, 3'd0, 15'd10080, 15'd0,
                              8'd61, 8'd30, 6'd12, 6'd12, 8'd0, 1'b0};
            3: descriptor = '{OP_CONV, BACKEND_DCIM, 3'd1, 15'd0, 15'd5400,
                              8'd30, 8'd15, 6'd12, 6'd12, 8'd108, 1'b1};
            4: descriptor = '{OP_POOL, BACKEND_POOL, 3'd0, 15'd5400, 15'd0,
                              8'd28, 8'd13, 6'd12, 6'd12, 8'd0, 1'b0};
            5: descriptor = '{OP_CONV, BACKEND_DCIM, 3'd2, 15'd0, 15'd1008,
                              8'd14, 8'd6, 6'd12, 6'd12, 8'd108, 1'b1};
            6: descriptor = '{OP_POOL, BACKEND_POOL, 3'd0, 15'd1008, 15'd0,
                              8'd12, 8'd4, 6'd12, 6'd12, 8'd0, 1'b0};
            7: descriptor = '{OP_FC, BACKEND_PE, 3'd3, 15'd0, 15'd144,
                              8'd0, 8'd0, 6'd0, 6'd32, 8'd144, 1'b1};
            8: descriptor = '{OP_FC, BACKEND_PE, 3'd4, 15'd144, 15'd0,
                              8'd0, 8'd0, 6'd0, 6'd8, 8'd32, 1'b0};
            default: descriptor_valid = 1'b0;
        endcase
    end
endmodule
