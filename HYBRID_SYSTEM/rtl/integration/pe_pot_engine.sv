`timescale 1ns/1ps
// One resident weight layer, one patch/vector per compute command.
// Model contract: uint8 zp128, signed int8 weights, no bias, fixed PoT ROM.
// compute_layer_id/relu_enable are captured at the compute handshake.
// Completion includes downstream acceptance of ALL quantized channels.
module pe_pot_engine #(
    parameter bit PE8_MODE=1'b1,
    parameter bit RESULT_PIPELINED=1'b0,
    parameter bit POSTPROCESS_PIPELINED=1'b1
) (
    input logic clk, rst,
    input logic load_valid, output wire load_ready,
    input logic [7:0] load_k,
    input logic [5:0] load_channels,
    output wire load_busy, load_done, load_error, layer_ready,
    input logic weight_valid, output wire weight_ready,
    input logic signed [7:0] weight_i8,
    input logic compute_valid, output wire compute_ready,
    input logic [2:0] compute_layer_id,
    input logic relu_enable,
    output wire compute_busy,
    output logic compute_done, compute_error,
    output wire replay_valid, input logic replay_ready,
    output wire [7:0] replay_k,
    output wire [4:0] replay_channel_base,
    input logic activation_valid, output wire activation_ready,
    input logic [7:0] activation_u8,
    output wire out_valid, input logic out_ready,
    output wire [7:0] out_data,
    output wire [4:0] out_channel_id,
    output wire out_group_last, out_error
);
    logic active, core_finished;
    logic [5:0] channels, retired;
    logic [2:0] layer_q;
    logic relu_q;
    wire core_load_ready, core_compute_ready, core_busy, core_done, core_error;
    wire raw_valid, raw_ready, raw_last, raw_error;
    wire signed [31:0] raw_data;
    wire [4:0] raw_channel;
    wire compute_fire=compute_valid && compute_ready;
    assign load_ready=!rst && !active && core_load_ready;
    assign compute_ready=!rst && !active && core_compute_ready;
    assign compute_busy=!rst && active;
    pe_memory_engine #(.PE8_MODE(PE8_MODE), .RESULT_PIPELINED(RESULT_PIPELINED),
        .INPUT_ZERO_POINT(128)) core (
        .clk(clk), .rst(rst), .load_valid(load_valid && !active),
        .load_ready(core_load_ready), .load_k(load_k), .load_channels(load_channels),
        .load_busy(load_busy), .load_done(load_done), .load_error(load_error), .layer_ready(layer_ready),
        .weight_valid(weight_valid), .weight_ready(weight_ready), .weight_i8(weight_i8),
        .compute_valid(compute_valid && !active), .compute_ready(core_compute_ready),
        .compute_busy(core_busy), .compute_done(core_done), .compute_error(core_error),
        .replay_valid(replay_valid), .replay_ready(replay_ready), .replay_k(replay_k),
        .replay_channel_base(replay_channel_base), .activation_valid(activation_valid),
        .activation_ready(activation_ready), .activation_u8(activation_u8),
        .out_valid(raw_valid), .out_ready(raw_ready), .out_data(raw_data),
        .out_channel_id(raw_channel), .out_group_last(raw_last), .out_error(raw_error)
    );
    pot_result_stream #(.POSTPROCESS_PIPELINED(POSTPROCESS_PIPELINED)) postprocess (
        .clk(clk), .rst(rst), .in_valid(raw_valid), .in_ready(raw_ready),
        .accumulator(raw_data), .layer_id(layer_q), .channel_id(raw_channel),
        .in_last(raw_last), .in_error(raw_error), .relu_enable(relu_q),
        .out_valid(out_valid), .out_ready(out_ready), .output_uint8(out_data),
        .out_channel_id(out_channel_id), .out_last(out_group_last), .out_error(out_error)
    );
    always_ff @(posedge clk) begin
        if(rst) begin
            active<=0; core_finished<=0; channels<=0; retired<=0;
            layer_q<=0; relu_q<=0; compute_done<=0; compute_error<=0;
        end else begin
            compute_done<=0;
            if(load_valid && load_ready) channels<=load_channels;
            if(compute_fire) begin
                active<=1; core_finished<=0; retired<=0; compute_error<=0;
                layer_q<=compute_layer_id; relu_q<=relu_enable;
            end else if(active) begin
                if(core_done) core_finished<=1;
                if(core_error || (out_valid && out_ready && out_error)) compute_error<=1;
                if(out_valid && out_ready) retired<=retired+1'b1;
                if(core_finished && retired==channels) begin
                    active<=0; compute_done<=1;
                end
            end
        end
    end
endmodule
