`timescale 1ns/1ps

module tb_maxpool2x2_uint8;

    logic clk = 1'b0;
    logic rst;
    logic frame_start;
    logic in_valid;
    logic [7:0] input_uint8;
    logic [7:0] input_width;
    logic [7:0] input_height;
    logic [4:0] input_channels;
    logic out_valid;
    logic [7:0] output_uint8;
    logic [4:0] output_channel;
    logic [6:0] output_y;
    logic [6:0] output_x;
    logic out_frame_done;

    integer error_count;
    integer output_count;

    always #5 clk = ~clk;

    maxpool2x2_uint8 #(.MAX_INPUT_WIDTH(126)) dut (
        .clk(clk), .rst(rst), .frame_start(frame_start),
        .in_valid(in_valid), .input_uint8(input_uint8),
        .input_width(input_width), .input_height(input_height),
        .input_channels(input_channels), .out_valid(out_valid),
        .output_uint8(output_uint8), .output_channel(output_channel),
        .output_y(output_y), .output_x(output_x),
        .out_frame_done(out_frame_done)
    );

    task automatic send_pixel;
        input logic [7:0] value;
        input logic first_pixel;
        begin
            @(negedge clk);
            input_uint8 = value;
            frame_start = first_pixel;
            in_valid    = 1'b1;
            @(posedge clk);
            #1;
            in_valid    = 1'b0;
            frame_start = 1'b0;
        end
    endtask

    task automatic expect_output;
        input logic [7:0] expected_value;
        input logic [4:0] expected_channel;
        input logic [6:0] expected_y;
        input logic [6:0] expected_x;
        input logic       expected_done;
        begin
            output_count = output_count + 1;
            if ((output_uint8 !== expected_value) ||
                (output_channel !== expected_channel) ||
                (output_y !== expected_y) || (output_x !== expected_x) ||
                (out_frame_done !== expected_done)) begin
                $display("FAIL output %0d: expected c/y/x=%0d/%0d/%0d value=%0d done=%0b; got %0d/%0d/%0d value=%0d done=%0b",
                         output_count, expected_channel, expected_y, expected_x,
                         expected_value, expected_done, output_channel,
                         output_y, output_x, output_uint8, out_frame_done);
                error_count = error_count + 1;
            end else begin
                $display("PASS output %0d: c/y/x=%0d/%0d/%0d value=%0d done=%0b",
                         output_count, output_channel, output_y, output_x,
                         output_uint8, out_frame_done);
            end
        end
    endtask

    always @(posedge clk) begin
        #2;
        if (out_valid) begin
            if (output_count == 0)
                expect_output(8'd6, 5'd0, 7'd0, 7'd0, 1'b0);
            else if (output_count == 1)
                expect_output(8'd8, 5'd0, 7'd0, 7'd1, 1'b1);
            else begin
                $display("FAIL: unexpected extra pool output %0d", output_uint8);
                error_count = error_count + 1;
            end
        end
    end

    initial begin
        rst = 1'b1;
        frame_start = 1'b0;
        in_valid = 1'b0;
        input_uint8 = 8'd0;
        input_width = 8'd5;
        input_height = 8'd3;
        input_channels = 5'd1;
        error_count = 0;
        output_count = 0;

        $display("============================================================");
        $display("Testbench: maxpool2x2_uint8");
        $display("Input 1x3x5; expected floor output 1x1x2 = {6,8}");
        $display("Large values in the final row/column must be discarded");
        $display("============================================================");

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        send_pixel(8'd1,   1'b1);
        send_pixel(8'd2,   1'b0);
        send_pixel(8'd3,   1'b0);
        send_pixel(8'd4,   1'b0);
        send_pixel(8'd99,  1'b0);
        send_pixel(8'd5,   1'b0);
        send_pixel(8'd6,   1'b0);
        send_pixel(8'd7,   1'b0);
        send_pixel(8'd8,   1'b0);
        send_pixel(8'd100, 1'b0);
        send_pixel(8'd200, 1'b0);
        send_pixel(8'd201, 1'b0);
        send_pixel(8'd202, 1'b0);
        send_pixel(8'd203, 1'b0);
        send_pixel(8'd204, 1'b0);

        repeat (3) @(posedge clk);
        if (output_count != 2) begin
            $display("FAIL: expected 2 outputs, got %0d", output_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("ALL MAXPOOL TESTS PASSED");
        else
            $fatal(1, "MAXPOOL TEST FAILED: %0d errors", error_count);
        $finish;
    end

endmodule
