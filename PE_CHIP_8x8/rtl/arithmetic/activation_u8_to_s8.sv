`timescale 1ns/1ps

// Re-encode UINT8 as signed (A - 128), NOT (A - 127).
module activation_u8_to_s8 (
    input  logic [7:0] activation_u8,
    output logic signed [7:0] activation_s8
);
    assign activation_s8 = $signed({~activation_u8[7], activation_u8[6:0]});
endmodule
