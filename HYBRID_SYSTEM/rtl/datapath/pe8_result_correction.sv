`timescale 1ns/1ps

// For raw=sum((A-128)*W), model activation zp=127, weight zp=0.
// One elastic register stage; bias is deliberately not supported.
module pe8_result_correction #(
    parameter integer CHANNEL_ID_WIDTH = 5
) (
    input logic clk,
    input logic rst,
    input logic in_valid,
    output logic in_ready,
    input logic signed [31:0] raw_accumulator,
    input logic signed [31:0] weight_sum,
    input logic [CHANNEL_ID_WIDTH-1:0] in_channel_id,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] corrected_accumulator,
    output logic [CHANNEL_ID_WIDTH-1:0] out_channel_id,
    output logic out_overflow
);
    logic signed [32:0] extended_sum;

    assign extended_sum = $signed({raw_accumulator[31], raw_accumulator})
                        + $signed({weight_sum[31], weight_sum});
    assign in_ready = !rst && (!out_valid || out_ready);

    always_ff @(posedge clk) begin
        if (rst) begin
            out_valid <= 1'b0;
            corrected_accumulator <= 32'sd0;
            out_channel_id <= '0;
            out_overflow <= 1'b0;
        end else if (in_ready) begin
            out_valid <= in_valid;
            if (in_valid) begin
                out_channel_id <= in_channel_id;
                out_overflow <= extended_sum[32] != extended_sum[31];
                if (extended_sum[32] != extended_sum[31])
                    corrected_accumulator <= extended_sum[32]
                        ? 32'sh80000000 : 32'sh7fffffff;
                else
                    corrected_accumulator <= extended_sum[31:0];
            end
        end
    end
endmodule
