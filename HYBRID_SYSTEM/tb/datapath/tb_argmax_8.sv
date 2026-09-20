`timescale 1ns/1ps

module tb_argmax_8;

    logic clk = 1'b0;
    logic rst;
    logic clear;
    logic in_valid;
    logic [7:0] input_uint8;
    logic out_valid;
    logic [2:0] class_index;
    logic [7:0] maximum_value;
    integer error_count;

    always #5 clk = ~clk;

    argmax_8 dut (
        .clk(clk), .rst(rst), .clear(clear), .in_valid(in_valid),
        .input_uint8(input_uint8), .out_valid(out_valid),
        .class_index(class_index), .maximum_value(maximum_value)
    );

    task automatic send_value;
        input logic [7:0] value;
        begin
            @(negedge clk);
            input_uint8 = value;
            in_valid = 1'b1;
            @(posedge clk);
            #1;
            in_valid = 1'b0;
        end
    endtask

    task automatic check_result;
        input logic [2:0] expected_index;
        input logic [7:0] expected_value;
        begin
            if (!out_valid || class_index !== expected_index ||
                maximum_value !== expected_value) begin
                $display("FAIL: expected index/value=%0d/%0d got=%0d/%0d valid=%0b",
                         expected_index, expected_value, class_index,
                         maximum_value, out_valid);
                error_count = error_count + 1;
            end else begin
                $display("PASS: argmax index=%0d value=%0d",
                         class_index, maximum_value);
            end
        end
    endtask

    initial begin
        rst = 1'b1;
        clear = 1'b0;
        in_valid = 1'b0;
        input_uint8 = 8'd0;
        error_count = 0;

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Actual FC2 export: 91 171 142 102 80 91 104 94.
        send_value(8'd91);
        send_value(8'd171);
        send_value(8'd142);
        send_value(8'd102);
        send_value(8'd80);
        send_value(8'd91);
        send_value(8'd104);
        send_value(8'd94);
        check_result(3'd1, 8'd171);

        // Tie case: indices 2 and 5 are both 200.  torch.argmax keeps 2.
        send_value(8'd10);
        send_value(8'd20);
        send_value(8'd200);
        send_value(8'd40);
        send_value(8'd50);
        send_value(8'd200);
        send_value(8'd70);
        send_value(8'd80);
        check_result(3'd2, 8'd200);

        if (error_count == 0)
            $display("ALL ARGMAX TESTS PASSED");
        else
            $fatal(1, "ARGMAX TEST FAILED: %0d errors", error_count);
        $finish;
    end

endmodule
