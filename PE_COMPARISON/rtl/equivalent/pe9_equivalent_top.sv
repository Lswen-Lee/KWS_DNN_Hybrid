`timescale 1ns/1ps
// Stream compute comparison top. No physical board pins or weight RAM.
module pe9_equivalent_top (
    input logic clk, rst,
    input logic cmd_valid,
    output logic cmd_ready,
    input logic [7:0] cmd_k,
    input logic [11:0] cmd_lane_mask,
    input logic in_valid,
    output logic in_ready,
    input logic [7:0] activation_u8,
    input logic [95:0] weights_flat,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] result,
    output logic [3:0] lane_id,
    output logic out_last, out_overflow, busy, done
);
    pe_compare_engine #(.PE8(0)) engine (
        .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_k(cmd_k), .cmd_lane_mask(cmd_lane_mask),
        .in_valid(in_valid), .in_ready(in_ready), .activation_u8(activation_u8),
        .weights_flat(weights_flat),
        .cfg_valid(1'b0), .cfg_ready(),
        .cfg_lane(4'b0), .cfg_weight_sum(32'sd0),
        .out_valid(out_valid), .out_ready(out_ready), .result(result),
        .lane_id(lane_id), .out_last(out_last), .out_overflow(out_overflow),
        .busy(busy), .done(done)
    );
endmodule
