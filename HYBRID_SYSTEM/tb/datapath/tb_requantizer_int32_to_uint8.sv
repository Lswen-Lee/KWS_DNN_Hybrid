`timescale 1ns/1ps

module tb_requantizer_int32_to_uint8;

    logic clk = 1'b0;
    logic rst;
    logic in_valid;
    logic signed [31:0] accumulator;
    logic [31:0] multiplier_q31;
    logic [7:0] output_zero_point;
    logic out_valid;
    logic [7:0] output_uint8;

    integer error_count;
    integer test_count;

    always #5 clk = ~clk;

    requantizer_int32_to_uint8 dut (
        .clk              (clk),
        .rst              (rst),
        .in_valid         (in_valid),
        .accumulator      (accumulator),
        .multiplier_q31   (multiplier_q31),
        .output_zero_point(output_zero_point),
        .out_valid        (out_valid),
        .output_uint8     (output_uint8)
    );

    task automatic check_value;
        input logic signed [31:0] test_accumulator;
        input logic        [31:0] test_multiplier;
        input logic         [7:0] test_zero_point;
        input logic         [7:0] expected;
        begin
            @(negedge clk);
            accumulator      = test_accumulator;
            multiplier_q31   = test_multiplier;
            output_zero_point = test_zero_point;
            in_valid         = 1'b1;

            @(negedge clk);
            in_valid = 1'b0;

            while (!out_valid)
                @(negedge clk);

            test_count = test_count + 1;
            if (output_uint8 !== expected) begin
                $display("FAIL test %0d: acc=%0d multiplier=%0d expected=%0d got=%0d",
                         test_count, test_accumulator, test_multiplier,
                         expected, output_uint8);
                error_count = error_count + 1;
            end else begin
                $display("PASS test %0d: acc=%0d -> UINT8=%0d",
                         test_count, test_accumulator, output_uint8);
            end
        end
    endtask

    initial begin
        rst               = 1'b1;
        in_valid          = 1'b0;
        accumulator       = 32'sd0;
        multiplier_q31    = 32'd0;
        output_zero_point = 8'd127;
        error_count       = 0;
        test_count        = 0;

        $display("============================================================");
        $display("Testbench: requantizer_int32_to_uint8");
        $display("Q31 formula and real Conv1 golden values");
        $display("============================================================");

        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Real Conv1 filter-0 values from dataset_index 1362.
        check_value( 32'sd5872,  32'd4157385, 8'd127, 8'd138);
        check_value( 32'sd7241,  32'd4157385, 8'd127, 8'd141);
        check_value( 32'sd6437,  32'd4157385, 8'd127, 8'd139);
        check_value(-32'sd2219,  32'd4157385, 8'd127, 8'd123);
        check_value(-32'sd38754, 32'd4157385, 8'd127, 8'd52);

        // Real Conv1 filter-1 and filter-3 use different per-channel scales.
        check_value( 32'sd5935,  32'd3133518, 8'd127, 8'd136);
        check_value(-32'sd36233, 32'd3133518, 8'd127, 8'd74);
        check_value( 32'sd633,   32'd1991215, 8'd127, 8'd128);

        // Q31=0.5 boundary cases verify zero-point and UINT8 saturation.
        check_value( 32'sd0,     32'h40000000, 8'd127, 8'd127);
        check_value( 32'sd2000,  32'h40000000, 8'd127, 8'd255);
        check_value(-32'sd2000,  32'h40000000, 8'd127, 8'd0);

        if (error_count == 0)
            $display("ALL REQUANTIZER TESTS PASSED (%0d tests)", test_count);
        else
            $fatal(1, "REQUANTIZER TEST FAILED: %0d errors", error_count);

        $finish;
    end

endmodule
