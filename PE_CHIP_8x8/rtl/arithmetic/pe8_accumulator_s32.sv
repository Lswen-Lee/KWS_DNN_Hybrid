`timescale 1ns/1ps

// Synchronous active-high reset. Priority: rst > clear > enable > hold.
// Signed addition wraps modulo 2^32; no saturation or quantization.
module pe8_accumulator_s32 (
    input  logic clk,
    input  logic rst,
    input  logic clear,
    input  logic accumulate_en,
    input  logic signed [15:0] product,
    output logic signed [31:0] accumulator
);
    logic signed [31:0] product_extended;
    assign product_extended = {{16{product[15]}}, product};
    always_ff @(posedge clk) begin
        if (rst)
            accumulator <= 32'sd0;
        else if (clear)
            accumulator <= 32'sd0;
        else if (accumulate_en)
            accumulator <= accumulator + product_extended;
    end
endmodule
