`timescale 1ns/1ps

module tb_adder_tree_32x4;

    logic [3:0] row_product [0:31];
    logic [8:0] bank_sum;

    integer i;
    integer error_count;

    adder_tree_32x4 dut (
        .row_product (row_product),
        .bank_sum    (bank_sum)
    );

    initial begin
        error_count = 0;

        $display("============================================================");
        $display("Testbench : tb_adder_tree_32x4");
        $display("Purpose   : add 32 unsigned four-bit row values");
        $display("Maximum   : 32 x 15 = 480");
        $display("============================================================");

        // Test 1: all rows are zero.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'd0;
        #1;
        $display("Test 1 - all rows are 0       : expected=0,   actual=%0d", bank_sum);
        if (bank_sum !== 9'd0) begin
            $display("FAIL: Test 1");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1");
        end

        // Test 2: only one row contains the maximum four-bit value.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'd0;
        row_product[0] = 4'd15;
        #1;
        $display("Test 2 - only row 0 is 15     : expected=15,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd15) begin
            $display("FAIL: Test 2");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2");
        end

        // Test 3: example shown in the presentation: 15 + 15 = 30.
        row_product[1] = 4'd15;
        #1;
        $display("Test 3 - row 0 + row 1        : expected=30,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd30) begin
            $display("FAIL: Test 3");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3");
        end

        // Test 4: both presentation pairs: 15 + 15 + 3 + 3 = 36.
        row_product[2] = 4'd3;
        row_product[3] = 4'd3;
        #1;
        $display("Test 4 - 15 + 15 + 3 + 3      : expected=36,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd36) begin
            $display("FAIL: Test 4");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4");
        end

        // Test 5: every row contains binary 0001.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'b0001;
        #1;
        $display("Test 5 - 32 rows x 1           : expected=32,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd32) begin
            $display("FAIL: Test 5");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5");
        end

        // Test 6: every row contains binary 0010.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'b0010;
        #1;
        $display("Test 6 - 32 rows x 2           : expected=64,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd64) begin
            $display("FAIL: Test 6");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6");
        end

        // Test 7: every row contains binary 0100.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'b0100;
        #1;
        $display("Test 7 - 32 rows x 4           : expected=128, actual=%0d", bank_sum);
        if (bank_sum !== 9'd128) begin
            $display("FAIL: Test 7");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7");
        end

        // Test 8: every row contains binary 1000.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'b1000;
        #1;
        $display("Test 8 - 32 rows x 8           : expected=256, actual=%0d", bank_sum);
        if (bank_sum !== 9'd256) begin
            $display("FAIL: Test 8");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 8");
        end

        // Test 9: maximum bank result: 32 x 15 = 480.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = 4'd15;
        #1;
        $display("Test 9 - maximum result        : expected=480, actual=%0d", bank_sum);
        if (bank_sum !== 9'd480) begin
            $display("FAIL: Test 9");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 9");
        end

        // Test 10: values 0 through 15 are repeated twice.
        // The expected sum is 2 x (0 + 1 + ... + 15) = 240.
        for (i = 0; i < 32; i = i + 1)
            row_product[i] = i[3:0];
        #1;
        $display("Test 10 - 0 to 15 repeated     : expected=240, actual=%0d", bank_sum);
        if (bank_sum !== 9'd240) begin
            $display("FAIL: Test 10");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 10");
        end

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all 10 adder-tree tests passed");
        end else begin
            $display("FAIL: %0d adder-tree tests failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
