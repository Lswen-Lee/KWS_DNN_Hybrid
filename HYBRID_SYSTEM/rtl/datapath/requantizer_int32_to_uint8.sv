`timescale 1ns/1ps

// Convert one signed INT32 convolution/FC accumulator into the common
// unsigned 8-bit activation code used by the KWS model.
//
// multiplier_q31 is generated offline for every output channel:
//
//   multiplier_q31 = round((input_scale * weight_scale / output_scale) * 2^31)
//
// The datapath implements:
//
//   output = saturate_u8(round(accumulator * multiplier_q31 / 2^31)
//                        + output_zero_point)
//
// It accepts one input every clock.  out_valid is asserted three rising edges
// after the corresponding in_valid edge.  Reset is synchronous active-high.
module requantizer_int32_to_uint8 (
    input  logic               clk,
    input  logic               rst,
    input  logic               in_valid,
    input  logic signed [31:0] accumulator,
    input  logic        [31:0] multiplier_q31,
    input  logic         [7:0] output_zero_point,
    output logic               out_valid,
    output logic         [7:0] output_uint8
);

    logic                     valid_stage1;
    logic                     valid_stage2;
    logic signed       [63:0] product_stage1;
    logic signed       [63:0] scaled_stage2;
    logic               [7:0] zero_point_stage1;
    logic               [7:0] zero_point_stage2;

    logic signed       [31:0] multiplier_signed;
    logic signed       [63:0] shifted_with_zero_point;

    // The KWS real multipliers are all between 0 and 1, therefore their Q31
    // encodings are at most 32'h7fffffff and are positive signed values.
    assign multiplier_signed = $signed(multiplier_q31);

    // Round the magnitude to nearest and restore the sign.  This makes the
    // positive and negative paths symmetric.  The exported KWS vectors were
    // checked against this rule for every Conv/FC output in the sample.
    function automatic logic signed [63:0] round_q31;
        input logic signed [63:0] value;
        logic signed [63:0] magnitude;
        begin
            if (value >= 0) begin
                round_q31 = (value + 64'sd1073741824) >>> 31;
            end else begin
                magnitude = -value;
                round_q31 = -((magnitude + 64'sd1073741824) >>> 31);
            end
        end
    endfunction

    always_comb begin
        shifted_with_zero_point =
            $signed(scaled_stage2) +
            $signed({56'd0, zero_point_stage2});
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            valid_stage1      <= 1'b0;
            valid_stage2      <= 1'b0;
            out_valid         <= 1'b0;
            product_stage1    <= 64'sd0;
            scaled_stage2     <= 64'sd0;
            zero_point_stage1 <= 8'd0;
            zero_point_stage2 <= 8'd0;
            output_uint8      <= 8'd0;
        end else begin
            valid_stage1      <= in_valid;
            valid_stage2      <= valid_stage1;
            out_valid         <= valid_stage2;

            product_stage1    <= $signed(accumulator) * multiplier_signed;
            zero_point_stage1 <= output_zero_point;

            scaled_stage2     <= round_q31(product_stage1);
            zero_point_stage2 <= zero_point_stage1;

            if (shifted_with_zero_point < 0)
                output_uint8 <= 8'd0;
            else if (shifted_with_zero_point > 64'sd255)
                output_uint8 <= 8'd255;
            else
                output_uint8 <= shifted_with_zero_point[7:0];
        end
    end

endmodule
