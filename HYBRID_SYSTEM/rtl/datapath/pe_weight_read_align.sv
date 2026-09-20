`timescale 1ns/1ps
// Exclusive read adapter for pe_weight_buffer_12. Both blocks MUST share rst.
// Buffer owns the registered weights; this block owns matching metadata.
module pe_weight_read_align (
    input logic clk, rst,
    input logic in_valid,
    output logic in_ready,
    input logic [7:0] in_activation_u8,
    input logic [8:0] in_weight_addr,
    input logic in_last,
    output logic weight_rd_valid,
    input logic weight_rd_ready,
    output logic [8:0] weight_rd_addr,
    input logic weight_out_valid,
    output logic weight_out_ready,
    input logic [95:0] weight_data,
    output logic out_valid,
    input logic out_ready,
    output logic [7:0] out_activation_u8,
    output logic [95:0] out_weights,
    output logic out_last
);
    logic pending;
    wire output_fire = out_valid && out_ready;
    wire slot_available = !pending || output_fire;
    wire input_fire = in_valid && in_ready;
    assign out_valid = !rst && pending && weight_out_valid;
    assign weight_out_ready = !rst && pending && out_ready;
    assign weight_rd_valid = !rst && in_valid && slot_available;
    assign in_ready = !rst && weight_rd_ready && slot_available;
    assign weight_rd_addr = in_weight_addr;
    assign out_weights = weight_data;
    always_ff @(posedge clk) begin
        if (rst) begin
            pending <= 0;
            out_activation_u8 <= 0;
            out_last <= 0;
        end else if (input_fire) begin
            pending <= 1;
            out_activation_u8 <= in_activation_u8;
            out_last <= in_last;
        end else if (output_fire) pending <= 0;
    end
endmodule
