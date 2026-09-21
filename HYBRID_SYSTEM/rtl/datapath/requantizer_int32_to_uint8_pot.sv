`timescale 1ns/1ps
// UINT8 zp=128, power-of-two scales. No multiplier and no bias correction.
// q = clip_u8(round_to_nearest_even(accumulator / 2^shift_amount) + 128).
// shift_amount is per transaction, supported range 0..31 (no left shift).
// Three registered stages, II=1, no backpressure. Input sampled at E0 gives
// out_valid/data immediately after E2, exactly like the original Q31 module.
// Downstream must consume every valid output. Synchronous active-high reset.
module requantizer_int32_to_uint8_pot (
    input  logic clk, rst,
    input  logic in_valid,
    input  logic signed [31:0] accumulator,
    input  logic [4:0] shift_amount,
    output logic out_valid,
    output logic [7:0] output_uint8
);
    logic valid_stage1, valid_stage2;
    logic signed [31:0] quotient_stage1, rounded_stage2;
    logic increment_stage1;
    logic signed [31:0] quotient;
    logic [31:0] remainder_bits, half_value, remainder_mask;
    logic increment;

    always_comb begin
        quotient = $signed(accumulator) >>> shift_amount;
        remainder_mask = 32'd0;
        remainder_bits = 32'd0;
        half_value = 32'd0;
        increment = 1'b0;
        if (shift_amount != 0) begin
            // Low k two's-complement bits are a nonnegative remainder even
            // for negative ACC: ACC = floor(ACC/2^k)*2^k + remainder.
            remainder_mask = (32'd1 << shift_amount) - 32'd1;
            remainder_bits = $unsigned(accumulator) & remainder_mask;
            half_value = 32'd1 << (shift_amount - 5'd1);
            increment = (remainder_bits > half_value) ||
                        ((remainder_bits == half_value) && quotient[0]);
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_stage1 <= 0;
            valid_stage2 <= 0;
            out_valid <= 0;
            quotient_stage1 <= 0;
            increment_stage1 <= 0;
            rounded_stage2 <= 0;
            output_uint8 <= 0;
        end else begin
            valid_stage1 <= in_valid;
            valid_stage2 <= valid_stage1;
            out_valid <= valid_stage2;
            if (in_valid) begin
                quotient_stage1 <= quotient;
                increment_stage1 <= increment;
            end
            // k=0 has increment=0; k>=1 limits quotient to +/-2^30.
            // Therefore this signed 32-bit addition cannot overflow.
            if (valid_stage1)
                rounded_stage2 <= quotient_stage1 + $signed({31'd0, increment_stage1});
            if (valid_stage2) begin
                if (rounded_stage2 < -32'sd128) output_uint8 <= 8'd0;
                else if (rounded_stage2 > 32'sd127) output_uint8 <= 8'd255;
                // Signed byte + 128 is exactly sign-bit inversion.
                else output_uint8 <= {~rounded_stage2[7], rounded_stage2[6:0]};
            end
        end
    end
endmodule
