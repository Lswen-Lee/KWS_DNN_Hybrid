`timescale 1ns/1ps
// 12 logical banks, 2**ADDR_WIDTH bytes each. One write or parallel read per
// edge. Memory is NOT reset. Caller must track which weights were loaded.
module pe_weight_buffer_12 #(
    parameter integer ADDR_WIDTH = 8
) (
    input logic clk, rst,
    input logic wr_valid,
    output logic wr_ready,
    input logic [3:0] wr_lane,
    input logic [ADDR_WIDTH-1:0] wr_addr,
    input logic [7:0] wr_data,
    input logic rd_valid,
    output logic rd_ready,
    input logic [ADDR_WIDTH-1:0] rd_addr,
    output logic out_valid,
    input logic out_ready,
    output wire [95:0] weights_flat
);
    wire write_fire = wr_valid && wr_ready;
    wire read_fire = rd_valid && rd_ready;
    assign wr_ready = !rst && wr_lane < 12;
    // Legal writes take priority. An invalid write must not starve reads.
    assign rd_ready = !rst && !write_fire && (!out_valid || out_ready);
    always_ff @(posedge clk) begin
        if (rst) out_valid <= 1'b0;
        else if (read_fire) out_valid <= 1'b1;
        else if (out_valid && out_ready) out_valid <= 1'b0;
    end
    genvar lane;
    generate for (lane=0; lane<12; lane=lane+1) begin : g_bank
        (* ram_style = "block" *) logic [7:0] memory [0:(2**ADDR_WIDTH)-1];
        logic [7:0] read_q;
        // No reset on RAM or read_q: preserve the block-RAM inference pattern.
        // Output CE isolates a stalled response from writes to the same addr.
        always @(posedge clk) begin
            if (write_fire && wr_lane == lane) memory[wr_addr] <= wr_data;
            if (read_fire) read_q <= memory[rd_addr];
        end
        assign weights_flat[lane*8 +: 8] = read_q;
    end endgenerate
endmodule
