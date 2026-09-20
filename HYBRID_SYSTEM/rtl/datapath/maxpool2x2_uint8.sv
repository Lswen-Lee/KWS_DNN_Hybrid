`timescale 1ns/1ps

// Reusable streaming 2x2 max-pool with stride 2 for channel-major UINT8
// feature maps.  Input order must be [channel][y][x], with x changing fastest.
// Odd final rows and columns are discarded, matching PyTorch floor behavior.
//
// frame_start may be asserted with the first valid pixel.  The width, height
// and channel count are latched on frame_start and must all be non-zero.
module maxpool2x2_uint8 #(
    parameter integer MAX_INPUT_WIDTH = 126
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       frame_start,
    input  logic       in_valid,
    input  logic [7:0] input_uint8,
    input  logic [7:0] input_width,
    input  logic [7:0] input_height,
    input  logic [4:0] input_channels,
    output logic       out_valid,
    output logic [7:0] output_uint8,
    output logic [4:0] output_channel,
    output logic [6:0] output_y,
    output logic [6:0] output_x,
    output logic       out_frame_done
);

    logic [7:0] line_buffer [0:MAX_INPUT_WIDTH-1];
    localparam integer LINE_ADDRESS_WIDTH = $clog2(MAX_INPUT_WIDTH);
    logic [LINE_ADDRESS_WIDTH-1:0] line_address;

    logic [7:0] configured_width;
    logic [7:0] configured_height;
    logic [4:0] configured_channels;
    logic [7:0] current_x;
    logic [7:0] current_y;
    logic [4:0] current_channel;
    logic       frame_active;

    logic [7:0] top_left;
    logic [7:0] bottom_left;
    logic [7:0] max_top;
    logic [7:0] max_bottom;
    logic [7:0] pooled_value;

    assign line_address = current_x[LINE_ADDRESS_WIDTH-1:0];

    always_comb begin
        if (top_left > line_buffer[line_address])
            max_top = top_left;
        else
            max_top = line_buffer[line_address];

        if (bottom_left > input_uint8)
            max_bottom = bottom_left;
        else
            max_bottom = input_uint8;

        if (max_top > max_bottom)
            pooled_value = max_top;
        else
            pooled_value = max_bottom;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            configured_width    <= 8'd0;
            configured_height   <= 8'd0;
            configured_channels <= 5'd0;
            current_x           <= 8'd0;
            current_y           <= 8'd0;
            current_channel     <= 5'd0;
            frame_active        <= 1'b0;
            top_left            <= 8'd0;
            bottom_left         <= 8'd0;
            out_valid           <= 1'b0;
            output_uint8        <= 8'd0;
            output_channel      <= 5'd0;
            output_y            <= 7'd0;
            output_x            <= 7'd0;
            out_frame_done      <= 1'b0;
        end else begin
            out_valid      <= 1'b0;
            out_frame_done <= 1'b0;

            // Start of a new feature map.  The first value is coordinate
            // channel=0, y=0, x=0 and can be accepted on this same edge.
            if (frame_start) begin
                configured_width    <= input_width;
                configured_height   <= input_height;
                configured_channels <= input_channels;
                current_x           <= 8'd0;
                current_y           <= 8'd0;
                current_channel     <= 5'd0;
                frame_active        <= 1'b1;

                if (in_valid) begin
                    line_buffer[0] <= input_uint8;

                    if (input_width > 8'd1) begin
                        current_x <= 8'd1;
                    end else begin
                        current_x <= 8'd0;
                        if (input_height > 8'd1) begin
                            current_y <= 8'd1;
                        end else if (input_channels > 5'd1) begin
                            current_y       <= 8'd0;
                            current_channel <= 5'd1;
                        end else begin
                            frame_active <= 1'b0;
                        end
                    end
                end
            end else if (frame_active && in_valid) begin
                // Even input rows are retained for the following odd row.
                if (!current_y[0]) begin
                    line_buffer[line_address] <= input_uint8;
                end else if (!current_x[0]) begin
                    // First column of a 2x2 window.
                    top_left    <= line_buffer[line_address];
                    bottom_left <= input_uint8;
                end else begin
                    // Second column completes the 2x2 window.
                    output_uint8   <= pooled_value;
                    output_channel <= current_channel;
                    output_y       <= current_y[7:1];
                    output_x       <= current_x[7:1];
                    out_valid      <= 1'b1;

                    if ((current_channel == configured_channels - 5'd1) &&
                        (current_y == ((configured_height >> 1) << 1) - 8'd1) &&
                        (current_x == ((configured_width  >> 1) << 1) - 8'd1))
                        out_frame_done <= 1'b1;
                end

                // Advance the channel-major input coordinates.
                if (current_x == configured_width - 8'd1) begin
                    current_x <= 8'd0;
                    if (current_y == configured_height - 8'd1) begin
                        current_y <= 8'd0;
                        if (current_channel == configured_channels - 5'd1) begin
                            current_channel <= 5'd0;
                            frame_active    <= 1'b0;
                        end else begin
                            current_channel <= current_channel + 5'd1;
                        end
                    end else begin
                        current_y <= current_y + 8'd1;
                    end
                end else begin
                    current_x <= current_x + 8'd1;
                end
            end
        end
    end

endmodule
