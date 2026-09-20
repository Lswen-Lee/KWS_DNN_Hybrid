`timescale 1ns/1ps

module tb_relu_uint8_zp127;

    logic clk = 1'b0;
    logic rst;
    logic enable;
    logic in_valid;
    logic [7:0] input_uint8;
    logic out_valid;
    logic [7:0] output_uint8;
    integer error_count;

    always #5 clk = ~clk;

    relu_uint8_zp127 dut (
        .clk(clk), .rst(rst), .enable(enable), .in_valid(in_valid),
        .input_uint8(input_uint8), .out_valid(out_valid),
        .output_uint8(output_uint8)
    );

    task automatic check_value;
        input logic test_enable;
        input logic [7:0] test_input;
        input logic [7:0] expected;
        begin
            @(negedge clk);
            enable      = test_enable;
            input_uint8 = test_input;
            in_valid    = 1'b1;
            @(posedge clk);
            #1;
            in_valid = 1'b0;

            if (!out_valid || output_uint8 !== expected) begin
                $display("FAIL: enable=%0b input=%0d expected=%0d got=%0d valid=%0b",
                         test_enable, test_input, expected, output_uint8, out_valid);
                error_count = error_count + 1;
            end else begin
                $display("PASS: enable=%0b input=%0d output=%0d",
                         test_enable, test_input, output_uint8);
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        enable = 1'b1;
        in_valid = 1'b0;
        input_uint8 = 8'd0;
        error_count = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        check_value(1'b1, 8'd0,   8'd127);
        check_value(1'b1, 8'd126, 8'd127);
        check_value(1'b1, 8'd127, 8'd127);
        check_value(1'b1, 8'd200, 8'd200);
        check_value(1'b0, 8'd20,  8'd20);

        if (error_count == 0)
            $display("ALL RELU TESTS PASSED");
        else
            $fatal(1, "RELU TEST FAILED: %0d errors", error_count);
        $finish;
    end

endmodule
