`timescale 1ns/1ps
// Downstream of requant/ReLU FIFO. Consume ONLY accepted FIFO transactions.
// mode 0=bypass, 1=CHW pooling, 2=FC2 class-order argmax.
// No downstream backpressure: the receiver must accept output pulses.
// Keep configuration stable until all frame results have drained.
module postprocess_tail (
    input logic clk, rst,
    input logic [1:0] mode,
    input logic accept, frame_start, argmax_clear,
    input logic [7:0] data_in, width, height,
    input logic [4:0] channels,
    output wire pool_valid, pool_done,
    output wire [7:0] pool_data,
    output wire [4:0] pool_channel,
    output wire [6:0] pool_y, pool_x,
    output wire argmax_valid,
    output wire [2:0] class_index,
    output wire [7:0] maximum_value
);
    maxpool2x2_uint8 #(.MAX_INPUT_WIDTH(126)) pool (
        .clk(clk),.rst(rst),.frame_start(accept && mode==1 && frame_start),
        .in_valid(accept && mode==1),.input_uint8(data_in),
        .input_width(width),.input_height(height),.input_channels(channels),
        .out_valid(pool_valid),.output_uint8(pool_data),.output_channel(pool_channel),
        .output_y(pool_y),.output_x(pool_x),.out_frame_done(pool_done));
    argmax_8 argmax (
        .clk(clk),.rst(rst),.clear(argmax_clear),
        .in_valid(accept && mode==2),.input_uint8(data_in),
        .out_valid(argmax_valid),.class_index(class_index),.maximum_value(maximum_value));
endmodule
