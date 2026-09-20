`timescale 1ns/1ps

// Convert the model's stored UINT8 activation code into the signed value used
// by every PE multiplier.
//
//   activation_centered = activation_u8 - 127
//
// The leading zero is essential.  It preserves codes 128..255 as positive
// unsigned values before the signed subtraction.  The result is signed 9-bit
// because the complete legal output range is -127..128.
//
// This is intentionally pure combinational logic.  The shared input pipeline
// in pe_core_12 will register the centered value before broadcasting it to the
// twelve MAC lanes.
module activation_center_127 (
    input  logic        [7:0] activation_u8,
    output logic signed [8:0] activation_centered
);

    always_comb begin
        activation_centered =
            $signed({1'b0, activation_u8}) - 9'sd127;
    end

endmodule
