`timescale 1ns/1ps

module tb_bank_output_or_tree;

    logic [8:0] even_bank_sum [0:15];
    logic [8:0] odd_bank_sum  [0:15];
    logic [8:0] selected_even_sum;
    logic [8:0] selected_odd_sum;

    logic [8:0] expected_even;
    logic [8:0] expected_odd;
    integer pair_index;
    integer clear_index;
    integer error_count;
    integer errors_before_test;

    bank_output_or_tree dut (
        .even_bank_sum     (even_bank_sum),
        .odd_bank_sum      (odd_bank_sum),
        .selected_even_sum (selected_even_sum),
        .selected_odd_sum  (selected_odd_sum)
    );

    task automatic clear_all_inputs;
        begin
            for (clear_index = 0; clear_index < 16; clear_index = clear_index + 1) begin
                even_bank_sum[clear_index] = 9'd0;
                odd_bank_sum[clear_index]  = 9'd0;
            end
        end
    endtask

    initial begin
        error_count  = 0;
        errors_before_test = 0;
        expected_even = 9'd0;
        expected_odd  = 9'd0;
        clear_all_inputs();

        $display("================================================================================");
        $display("Testbench : tb_bank_output_or_tree");
        $display("Purpose   : OR-select 16 even and 16 odd nine-bit bank partial sums");
        $display("Structure : four OR4 groups followed by one final OR4 per output path");
        $display("Rule      : unselected banks are zero; only one pair is active normally");
        $display("================================================================================");

        // Test 1: an idle array must produce two zero outputs.
        #1;
        if ((selected_even_sum !== 9'd0) || (selected_odd_sum !== 9'd0)) begin
            $display("FAIL: Test 1 - all-zero inputs produced even=%0d odd=%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - all-zero inputs produce two zero outputs");
        end

        // Test 2: select pair 0 with different even and odd values.
        clear_all_inputs();
        even_bank_sum[0] = 9'd100;
        odd_bank_sum[0]  = 9'd200;
        #1;
        if ((selected_even_sum !== 9'd100) ||
            (selected_odd_sum !== 9'd200)) begin
            $display("FAIL: Test 2 - pair 0 expected even=100 odd=200, actual even=%0d odd=%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - pair 0 keeps even=100 and odd=200 independent");
        end

        // Test 3: exhaust every pair position.  The values remain inside the
        // legal 0..480 range of one 32x4 bank and differ on the two paths.
        errors_before_test = error_count;
        for (pair_index = 0; pair_index < 16; pair_index = pair_index + 1) begin
            clear_all_inputs();
            expected_even = (pair_index[3:0] * 9'd29) + 9'd7;
            expected_odd  = 9'd480 - (pair_index[3:0] * 9'd17);
            even_bank_sum[pair_index] = expected_even;
            odd_bank_sum[pair_index]  = expected_odd;
            #1;

            $display("Pair %2d (segments %2d/%2d) -> expected E/O=%3d/%3d, actual E/O=%3d/%3d",
                     pair_index, pair_index * 2, pair_index * 2 + 1,
                     expected_even, expected_odd,
                     selected_even_sum, selected_odd_sum);

            if ((selected_even_sum !== expected_even) ||
                (selected_odd_sum !== expected_odd)) begin
                $display("FAIL: Test 3 - wrong OR-tree connection at pair %0d",
                         pair_index);
                error_count = error_count + 1;
            end
        end
        if (error_count == errors_before_test)
            $display("PASS: Test 3 - all 16 pair positions and OR4 boundaries are correct");

        // Test 4: verify that activity on one path cannot leak into the other.
        errors_before_test = error_count;
        clear_all_inputs();
        even_bank_sum[6] = 9'd321;
        #1;
        if ((selected_even_sum !== 9'd321) ||
            (selected_odd_sum !== 9'd0)) begin
            $display("FAIL: Test 4a - even-only input leaked or changed");
            error_count = error_count + 1;
        end

        clear_all_inputs();
        odd_bank_sum[9] = 9'd123;
        #1;
        if ((selected_even_sum !== 9'd0) ||
            (selected_odd_sum !== 9'd123)) begin
            $display("FAIL: Test 4b - odd-only input leaked or changed");
            error_count = error_count + 1;
        end
        if (error_count == errors_before_test) begin
            $display("PASS: Test 4 - even and odd output trees are isolated");
        end

        // Test 5: check the maximum legal sum at the last pair boundary.
        clear_all_inputs();
        even_bank_sum[15] = 9'd480;
        odd_bank_sum[15]  = 9'd480;
        #1;
        if ((selected_even_sum !== 9'd480) ||
            (selected_odd_sum !== 9'd480)) begin
            $display("FAIL: Test 5 - maximum 9-bit partial sum was not preserved");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - pair 15 preserves maximum result 480");
        end

        // Test 6: alternating bit patterns expose bit-order or path swaps.
        clear_all_inputs();
        even_bank_sum[3] = 9'b101010101;
        odd_bank_sum[3]  = 9'b010101010;
        #1;
        if ((selected_even_sum !== 9'b101010101) ||
            (selected_odd_sum !== 9'b010101010)) begin
            $display("FAIL: Test 6 - alternating bit patterns changed");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - all nine bits keep their order");
        end

        // Test 7: multi-active input is illegal in normal operation, but the
        // module must still perform bitwise OR rather than arithmetic add.
        clear_all_inputs();
        even_bank_sum[0]  = 9'b000001111;
        even_bank_sum[15] = 9'b111100000;
        odd_bank_sum[4]   = 9'b001010101;
        odd_bank_sum[12]  = 9'b100101010;
        expected_even     = 9'b111101111;
        expected_odd      = 9'b101111111;
        #1;
        if ((selected_even_sum !== expected_even) ||
            (selected_odd_sum !== expected_odd)) begin
            $display("FAIL: Test 7 - multi-active bitwise OR is incorrect");
            $display("      expected E/O=%09b/%09b, actual E/O=%09b/%09b",
                     expected_even, expected_odd,
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - illegal multi-active input still performs bitwise OR");
        end

        clear_all_inputs();
        #1;

        $display("================================================================================");
        if (error_count == 0) begin
            $display("PASS: all bank-output-OR-tree tests passed");
        end else begin
            $display("FAIL: %0d bank-output-OR-tree checks failed", error_count);
            $fatal(1);
        end
        $display("================================================================================");

        $finish;
    end

endmodule
