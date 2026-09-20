`timescale 1ns/1ps
// Emit enabled lanes in increasing order. Disabled lanes consume one scan
// clock each; explicit, identical policy for both comparison tops.
module pe_compare_result_drain (
    input logic clk, rst, clear, active,
    input logic [11:0] lane_mask,
    input logic [383:0] results,
    output logic valid,
    input logic ready,
    output logic signed [31:0] data,
    output logic [3:0] lane,
    output logic last,
    output logic empty
);
    logic exhausted;
    logic [11:0] higher_lanes;
    assign higher_lanes = lane_mask >> (int'(lane) + 1);
    assign valid = !rst && active && !exhausted && lane_mask[lane];
    assign data = $signed(results[int'(lane)*32 +: 32]);
    assign last = higher_lanes == 0;
    assign empty = lane_mask == 0;
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            lane <= 0;
            exhausted <= 0;
        end else if (active && !exhausted) begin
            if (!lane_mask[lane] || (valid && ready)) begin
                if (lane == 11 || (valid && ready && last)) exhausted <= 1;
                else lane <= lane + 1'b1;
            end
        end
    end
endmodule
