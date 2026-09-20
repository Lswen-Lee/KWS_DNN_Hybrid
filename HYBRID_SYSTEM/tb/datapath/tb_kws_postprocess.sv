`timescale 1ns/1ps

module tb_kws_postprocess;

    logic clk = 1'b0;
    logic rst;
    logic in_valid;
    logic in_frame_start;
    logic in_frame_last;
    logic signed [31:0] accumulator;
    logic [31:0] multiplier_q31;
    logic [7:0] output_zero_point;
    logic relu_enable;
    logic pool_enable;
    logic [7:0] pool_input_width;
    logic [7:0] pool_input_height;
    logic [4:0] pool_input_channels;
    logic out_valid;
    logic [7:0] output_uint8;
    logic [4:0] output_channel;
    logic [6:0] output_y;
    logic [6:0] output_x;
    logic out_frame_done;

    integer error_count;

    always #5 clk = ~clk;

    kws_postprocess #(.MAX_INPUT_WIDTH(126)) dut (
        .clk(clk), .rst(rst), .in_valid(in_valid),
        .in_frame_start(in_frame_start), .in_frame_last(in_frame_last),
        .accumulator(accumulator), .multiplier_q31(multiplier_q31),
        .output_zero_point(output_zero_point), .relu_enable(relu_enable),
        .pool_enable(pool_enable), .pool_input_width(pool_input_width),
        .pool_input_height(pool_input_height),
        .pool_input_channels(pool_input_channels), .out_valid(out_valid),
        .output_uint8(output_uint8), .output_channel(output_channel),
        .output_y(output_y), .output_x(output_x),
        .out_frame_done(out_frame_done)
    );

    task automatic apply_reset;
        begin
            @(negedge clk);
            rst = 1'b1;
            in_valid = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic send_accumulator;
        input logic signed [31:0] value;
        input logic first_value;
        input logic last_value;
        begin
            @(negedge clk);
            accumulator   = value;
            in_frame_start = first_value;
            in_frame_last  = last_value;
            in_valid       = 1'b1;
            @(posedge clk);
            #1;
            in_valid       = 1'b0;
            in_frame_start = 1'b0;
            in_frame_last  = 1'b0;
        end
    endtask

    task automatic wait_and_check;
        input logic [7:0] expected_value;
        input logic       expected_done;
        begin
            while (!out_valid)
                @(negedge clk);

            if ((output_uint8 !== expected_value) ||
                (out_frame_done !== expected_done)) begin
                $display("FAIL: expected value/done=%0d/%0b got=%0d/%0b",
                         expected_value, expected_done,
                         output_uint8, out_frame_done);
                error_count = error_count + 1;
            end else begin
                $display("PASS: post-process output=%0d done=%0b",
                         output_uint8, out_frame_done);
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        in_valid = 1'b0;
        in_frame_start = 1'b0;
        in_frame_last = 1'b0;
        accumulator = 32'sd0;
        multiplier_q31 = 32'd4157385;
        output_zero_point = 8'd127;
        relu_enable = 1'b1;
        pool_enable = 1'b0;
        pool_input_width = 8'd2;
        pool_input_height = 8'd2;
        pool_input_channels = 5'd1;
        error_count = 0;

        $display("============================================================");
        $display("Testbench: kws_postprocess integration");
        $display("Checks requant+ReLU bypass and requant+ReLU+Pool");
        $display("============================================================");

        apply_reset();

        // Real Conv1 example: requant(-2219)=123, ReLU raises it to 127.
        multiplier_q31 = 32'd4157385;
        relu_enable = 1'b1;
        pool_enable = 1'b0;
        send_accumulator(-32'sd2219, 1'b1, 1'b1);
        wait_and_check(8'd127, 1'b1);

        apply_reset();

        // Q31=0.5 produces 128,132,130,131 after adding zero-point 127.
        // The single 2x2 pooling result must therefore be 132.
        multiplier_q31 = 32'h40000000;
        relu_enable = 1'b1;
        pool_enable = 1'b1;
        pool_input_width = 8'd2;
        pool_input_height = 8'd2;
        pool_input_channels = 5'd1;
        send_accumulator(32'sd2,  1'b1, 1'b0);
        send_accumulator(32'sd10, 1'b0, 1'b0);
        send_accumulator(32'sd6,  1'b0, 1'b0);
        send_accumulator(32'sd8,  1'b0, 1'b1);
        wait_and_check(8'd132, 1'b1);

        if ((output_channel !== 5'd0) || (output_y !== 7'd0) ||
            (output_x !== 7'd0)) begin
            $display("FAIL: integrated pool output coordinate is not 0/0/0");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("ALL POST-PROCESS INTEGRATION TESTS PASSED");
        else
            $fatal(1, "POST-PROCESS TEST FAILED: %0d errors", error_count);
        $finish;
    end

endmodule
