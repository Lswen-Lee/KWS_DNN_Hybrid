`timescale 1ns/1ps
// Fixed-configuration comparison boundary. No extra registers or control.
module pe8_pipeline_memory_top (
    input logic clk, rst,
    input logic load_valid,
    output logic load_ready,
    input logic [7:0] load_k,
    input logic [5:0] load_channels,
    output logic load_busy, load_done, load_error, layer_ready,
    input logic weight_valid,
    output logic weight_ready,
    input logic signed [7:0] weight_i8,
    input logic compute_valid,
    output logic compute_ready, compute_busy, compute_done, compute_error,
    output logic replay_valid,
    input logic replay_ready,
    output logic [7:0] replay_k,
    output logic [4:0] replay_channel_base,
    input logic activation_valid,
    output logic activation_ready,
    input logic [7:0] activation_u8,
    output logic out_valid,
    input logic out_ready,
    output logic signed [31:0] out_data,
    output logic [4:0] out_channel_id,
    output logic out_group_last, out_error
);
    pe_memory_engine #(.PE8_MODE(1'b1), .RESULT_PIPELINED(1'b1)) engine (.*);
endmodule
