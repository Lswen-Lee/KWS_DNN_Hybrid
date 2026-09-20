`timescale 1ns/1ps

// Signed multiplier used by one PE lane.
//
// The activation has already been centered by activation_center_127:
//
//   activation_centered = activation_u8 - 127
//   product             = activation_centered * weight_i8
//
// A signed 9-bit by signed 8-bit multiplication requires the full signed
// 17-bit result.  No rounding, saturation, truncation or requantization is
// performed in this module.
//
// Request LUT mapping in Vivado without changing the combinational interface.
// No pipeline register is inserted here; timing must be checked after routing.
(* use_dsp = "no" *)
module pe_multiplier_s9xs8 (
    input  logic signed [8:0]  activation_centered,
    input  logic signed [7:0]  weight_i8,
    output logic signed [16:0] product
);

    always_comb begin
        product = activation_centered * weight_i8;
    end

endmodule
