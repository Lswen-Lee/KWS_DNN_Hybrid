`timescale 1ns/1ps

// Signed INT32 accumulator used by one PE lane.
//
// Priority at every rising edge:
//
//   rst > clear > accumulate_en > hold
//
// rst is synchronous and active-high.  clear starts a new dot-product without
// resetting the rest of the PE core.  The signed 17-bit product is explicitly
// sign-extended to 32 bits before addition.  This module intentionally does
// not perform saturation, rounding, bias addition or requantization.
module pe_accumulator_s32 (
    input  logic               clk,
    input  logic               rst,
    input  logic               clear,
    input  logic               accumulate_en,
    input  logic signed [16:0] product,
    output logic signed [31:0] accumulator
);

    logic signed [31:0] product_extended;

    always_comb begin
        product_extended = {{15{product[16]}}, product};
    end

    always_ff @(posedge clk) begin
        if (rst)
            accumulator <= 32'sd0;
        else if (clear)
            accumulator <= 32'sd0;
        else if (accumulate_en)
            accumulator <= accumulator + product_extended;
    end

endmodule
