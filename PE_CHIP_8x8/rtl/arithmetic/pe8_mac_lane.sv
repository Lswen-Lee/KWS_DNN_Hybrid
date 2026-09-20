`timescale 1ns/1ps
// LUT/FF implementation. Accept N, commit N+1; reset/clear flush pending work.
(* use_dsp = "no" *)
module pe8_mac_lane (
    input logic clk, rst, clear, accumulate_en,
    input logic signed [7:0] activation_s8, weight_i8,
    output logic signed [31:0] accumulator
);
    logic signed [15:0] product_reg;
    logic product_valid;
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            product_reg <= '0;
            product_valid <= 1'b0;
            accumulator <= '0;
        end else begin
            product_valid <= accumulate_en;
            if (accumulate_en) product_reg <= activation_s8 * weight_i8;
            if (product_valid)
                accumulator <= accumulator + {{16{product_reg[15]}}, product_reg};
        end
    end
endmodule
