`timescale 1ns/1ps
// Raw results only. For model zp=127, add sum(W) outside this array.
// Each lane has a product pipeline: drain one clock after the final input.
// No correction, K counter or result handshake is added.
module pe8_array_12 (
    input logic clk,
    input logic rst,
    input logic clear,
    input logic accumulate_en,
    input logic [pe8_pkg::LANE_COUNT-1:0] lane_mask,
    input pe8_pkg::activation_t activation_s8,
    input logic [pe8_pkg::WEIGHT_VECTOR_WIDTH-1:0] weight_vector_i8,
    output logic [pe8_pkg::RESULT_VECTOR_WIDTH-1:0] result_vector_s32
);
    import pe8_pkg::*;
    genvar lane;
    generate
        for(lane=0;lane<LANE_COUNT;lane=lane+1) begin : gen_lane
            weight_t lane_weight;
            accumulator_t lane_result;
            logic lane_enable;
            assign lane_weight=$signed(weight_vector_i8[lane*WEIGHT_WIDTH +: WEIGHT_WIDTH]);
            assign lane_enable=accumulate_en && lane_mask[lane];
            pe8_mac_lane mac_lane (
                .clk(clk), .rst(rst), .clear(clear),
                .accumulate_en(lane_enable), .activation_s8(activation_s8),
                .weight_i8(lane_weight), .accumulator(lane_result)
            );
            assign result_vector_s32[lane*ACC_WIDTH +: ACC_WIDTH]=lane_result;
        end
    endgenerate
endmodule
