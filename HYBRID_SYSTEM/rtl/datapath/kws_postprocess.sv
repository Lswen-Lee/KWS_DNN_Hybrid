`timescale 1ns/1ps

// Shared post-processing path for PE and corrected DCIM INT32 results.
// Layer controls and pooling dimensions must remain stable for one frame.
//
//   INT32 -> Q31 requantization -> optional ReLU -> optional 2x2 max-pool
//
// in_frame_start and in_frame_last are asserted with the first and last valid
// accumulator.  For pooled layers, out_frame_done accompanies the final pooled
// output.  For non-pooled layers it accompanies the final requantized/ReLU
// output.
module kws_postprocess #(
    parameter integer MAX_INPUT_WIDTH = 126
) (
    input  logic               clk,
    input  logic               rst,

    input  logic               in_valid,
    input  logic               in_frame_start,
    input  logic               in_frame_last,
    input  logic signed [31:0] accumulator,
    input  logic        [31:0] multiplier_q31,
    input  logic         [7:0] output_zero_point,

    input  logic               relu_enable,
    input  logic               pool_enable,
    input  logic         [7:0] pool_input_width,
    input  logic         [7:0] pool_input_height,
    input  logic         [4:0] pool_input_channels,

    output logic               out_valid,
    output logic         [7:0] output_uint8,
    output logic         [4:0] output_channel,
    output logic         [6:0] output_y,
    output logic         [6:0] output_x,
    output logic               out_frame_done
);

    logic       requant_valid;
    logic [7:0] requant_data;
    logic       relu_valid;
    logic [7:0] relu_data;

    logic [2:0] frame_start_pipe;
    logic [2:0] frame_last_pipe;
    logic       relu_frame_start;
    logic       relu_frame_last;

    logic       pool_valid;
    logic [7:0] pool_data;
    logic [4:0] pool_channel;
    logic [6:0] pool_y;
    logic [6:0] pool_x;
    logic       pool_frame_done;

    requantizer_int32_to_uint8 u_requantizer (
        .clk              (clk),
        .rst              (rst),
        .in_valid         (in_valid),
        .accumulator      (accumulator),
        .multiplier_q31   (multiplier_q31),
        .output_zero_point(output_zero_point),
        .out_valid        (requant_valid),
        .output_uint8     (requant_data)
    );

    relu_uint8_zp127 u_relu (
        .clk         (clk),
        .rst         (rst),
        .enable      (relu_enable),
        .in_valid    (requant_valid),
        .input_uint8 (requant_data),
        .out_valid   (relu_valid),
        .output_uint8(relu_data)
    );

    // Match the three requantizer stages and the one ReLU/bypass register.
    always_ff @(posedge clk) begin
        if (rst) begin
            frame_start_pipe <= 3'b000;
            frame_last_pipe  <= 3'b000;
            relu_frame_start <= 1'b0;
            relu_frame_last  <= 1'b0;
        end else begin
            frame_start_pipe[0] <= in_valid && in_frame_start;
            frame_start_pipe[1] <= frame_start_pipe[0];
            frame_start_pipe[2] <= frame_start_pipe[1];

            frame_last_pipe[0] <= in_valid && in_frame_last;
            frame_last_pipe[1] <= frame_last_pipe[0];
            frame_last_pipe[2] <= frame_last_pipe[1];

            relu_frame_start <= frame_start_pipe[2];
            relu_frame_last  <= frame_last_pipe[2];
        end
    end

    maxpool2x2_uint8 #(
        .MAX_INPUT_WIDTH(MAX_INPUT_WIDTH)
    ) u_maxpool (
        .clk             (clk),
        .rst             (rst),
        .frame_start     (relu_frame_start),
        .in_valid        (relu_valid),
        .input_uint8     (relu_data),
        .input_width     (pool_input_width),
        .input_height    (pool_input_height),
        .input_channels  (pool_input_channels),
        .out_valid       (pool_valid),
        .output_uint8    (pool_data),
        .output_channel  (pool_channel),
        .output_y        (pool_y),
        .output_x        (pool_x),
        .out_frame_done  (pool_frame_done)
    );

    always_comb begin
        if (pool_enable) begin
            out_valid       = pool_valid;
            output_uint8    = pool_data;
            output_channel  = pool_channel;
            output_y        = pool_y;
            output_x        = pool_x;
            out_frame_done  = pool_frame_done;
        end else begin
            out_valid       = relu_valid;
            output_uint8    = relu_data;
            output_channel  = 5'd0;
            output_y        = 7'd0;
            output_x        = 7'd0;
            out_frame_done  = relu_valid && relu_frame_last;
        end
    end

endmodule
