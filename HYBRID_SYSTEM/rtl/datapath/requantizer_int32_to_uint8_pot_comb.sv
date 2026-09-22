`timescale 1ns/1ps
// Pure combinational counterpart of the three-stage PoT quantizer.
// All shifts 0..31; signed floor quotient + nonnegative remainder implements
// round-to-nearest-even for BOTH signs. No clk/reset/valid or inferred latch.
module requantizer_int32_to_uint8_pot_comb (
    input logic signed [31:0] accumulator,
    input logic [4:0] shift_amount,
    output logic [7:0] output_uint8
);
    logic signed [31:0] quotient, rounded;
    logic [31:0] remainder_bits, half_value, remainder_mask;
    logic increment;
    always_comb begin
        quotient = $signed(accumulator) >>> shift_amount;
        remainder_mask = 32'd0;
        remainder_bits = 32'd0;
        half_value = 32'd0;
        increment = 1'b0;
        if (shift_amount != 0) begin
            remainder_mask = (32'd1 << shift_amount) - 32'd1;
            remainder_bits = $unsigned(accumulator) & remainder_mask;
            half_value = 32'd1 << (shift_amount - 5'd1);
            increment = (remainder_bits > half_value) ||
                        ((remainder_bits == half_value) && quotient[0]);
        end
        // k=0: increment=0; k>=1: quotient fits +/-2^30, so no overflow.
        rounded = quotient + $signed({31'd0, increment});
        if (rounded < -32'sd128) output_uint8 = 8'd0;
        else if (rounded > 32'sd127) output_uint8 = 8'd255;
        else output_uint8 = {~rounded[7], rounded[6:0]};
    end
endmodule
