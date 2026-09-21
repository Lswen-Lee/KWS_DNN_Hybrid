`timescale 1ns/1ps

// One-stage streaming ReLU for the model's unsigned activation format.
// Quantized real zero is ZERO_POINT (legacy default 127, PoT model 128),
// therefore ReLU is max(input, ZERO_POINT), not max(input, 0).
// When enable=0 the stage remains as a one-cycle pipeline
// register so that control/data latency does not change between layers.
module relu_uint8_zp127 #(
    parameter logic [7:0] ZERO_POINT = 8'd127
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       enable,
    input  logic       in_valid,
    input  logic [7:0] input_uint8,
    output logic       out_valid,
    output logic [7:0] output_uint8
);

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid    <= 1'b0;
            output_uint8 <= 8'd0;
        end else begin
            out_valid <= in_valid;

            if (enable && (input_uint8 < ZERO_POINT))
                output_uint8 <= ZERO_POINT;
            else
                output_uint8 <= input_uint8;
        end
    end

endmodule
