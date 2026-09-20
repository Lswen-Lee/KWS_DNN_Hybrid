`timescale 1ns/1ps
// One layer, 32 output channels. Synchronous read with one elastic response.
module pe_channel_sum_memory (
    input logic clk, rst, layer_clear,
    input logic wr_valid,
    output logic wr_ready,
    input logic [4:0] wr_channel_id,
    input logic signed [31:0] wr_weight_sum,
    input logic rd_valid,
    output logic rd_ready,
    input logic [4:0] rd_channel_id,
    output logic out_valid,
    input logic out_ready,
    output logic [4:0] out_channel_id,
    output logic signed [31:0] out_weight_sum,
    output logic out_error
);
    logic signed [31:0] sum_mem [0:31];
    logic [31:0] channel_valid;
    wire write_fire = wr_valid && wr_ready;
    wire read_fire = rd_valid && rd_ready;
    assign wr_ready = !rst && !layer_clear;
    assign rd_ready = !rst && !layer_clear && !write_fire
                      && (!out_valid || out_ready);
    // Data array deliberately has no reset. Only validity is cleared.
    always_ff @(posedge clk) begin
        if (write_fire) sum_mem[wr_channel_id] <= wr_weight_sum;
    end
    always_ff @(posedge clk) begin
        if (rst || layer_clear) begin
            channel_valid <= 0;
            out_valid <= 0;
            out_channel_id <= 0;
            out_weight_sum <= 0;
            out_error <= 0;
        end else begin
            if (write_fire) channel_valid[wr_channel_id] <= 1;
            if (read_fire) begin
                out_valid <= 1;
                out_channel_id <= rd_channel_id;
                out_error <= !channel_valid[rd_channel_id];
                out_weight_sum <= channel_valid[rd_channel_id]
                                  ? sum_mem[rd_channel_id] : 32'sd0;
            end else if (out_valid && out_ready) out_valid <= 0;
        end
    end
endmodule
