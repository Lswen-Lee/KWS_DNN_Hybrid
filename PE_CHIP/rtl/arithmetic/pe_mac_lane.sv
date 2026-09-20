`timescale 1ns/1ps
// LUT/FF implementation, aligned with pe8_mac_lane.
// Accept at edge N, accumulate at N+1; reset/clear discard pending products.
// Accumulation wraps modulo 2^32, preserving the former DSP public result.
(* use_dsp = "no" *)
module pe_mac_lane (
    input logic clk,
    input logic rst,
    input logic clear,
    input logic accumulate_en,
    input logic signed [8:0] activation_centered,
    input logic signed [7:0] weight_i8,
    output logic signed [31:0] accumulator
);
    logic signed [16:0] product_reg;
    logic product_valid;
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            product_reg <= '0;
            product_valid <= 1'b0;
            accumulator <= '0;
        end else begin
            product_valid <= accumulate_en;
            if (accumulate_en)
                product_reg <= activation_centered * weight_i8;
            if (product_valid)
                accumulator <= accumulator + {{15{product_reg[16]}}, product_reg};
        end
    end
endmodule
