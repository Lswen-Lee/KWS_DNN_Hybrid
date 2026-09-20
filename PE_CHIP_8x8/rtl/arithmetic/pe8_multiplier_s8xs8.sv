`timescale 1ns/1ps

// Explicitly request LUT logic; no latency or pipeline registers here.
(* use_dsp = "no" *)
module pe8_multiplier_s8xs8 (
    input  logic signed [7:0] activation_s8,
    input  logic signed [7:0] weight_i8,
    output logic signed [15:0] product
);

    assign product = activation_s8 * weight_i8;
    
endmodule
