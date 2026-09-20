`timescale 1ns/1ps

module tb_pe_multiplier_s9xs8;

    logic signed [8:0]  activation_centered;
    logic signed [7:0]  weight_i8;
    logic signed [16:0] product;
    logic signed [16:0] expected_product;

    integer activation_value;
    integer weight_value;
    integer golden_product;
    integer error_count;
    integer check_count;

    pe_multiplier_s9xs8 dut (
        .activation_centered (activation_centered),
        .weight_i8           (weight_i8),
        .product             (product)
    );

    task automatic check_case;
        input integer test_activation;
        input integer test_weight;
        input integer test_expected;
        begin
            activation_centered = test_activation[8:0];
            weight_i8           = test_weight[7:0];
            expected_product    = test_expected[16:0];
            #1;

            check_count = check_count + 1;
            if (product !== expected_product) begin
                $display("FAIL case %0d: activation=%0d weight=%0d expected=%0d got=%0d",
                         check_count, test_activation, test_weight,
                         test_expected, product);
                error_count = error_count + 1;
            end else begin
                $display("PASS case %0d: %0d * %0d = %0d",
                         check_count, test_activation, test_weight, product);
            end
        end
    endtask

    initial begin
        activation_centered = 9'sd0;
        weight_i8           = 8'sd0;
        expected_product    = 17'sd0;
        error_count         = 0;
        check_count         = 0;

        $display("============================================================");
        $display("Testbench : tb_pe_multiplier_s9xs8");
        $display("Equation  : product = signed9 activation * signed8 weight");
        $display("Activation: -127..128 (UINT8 code centered at 127)");
        $display("Weight    : -128..127");
        $display("Product   : signed 17-bit, no truncation or saturation");
        $display("============================================================");

        // Easy-to-read zero, sign and boundary checks.
        check_case(   0,    0,      0);
        check_case(   0, -128,      0);
        check_case(   1,  127,    127);
        check_case(   1, -128,   -128);
        check_case(  -1,  127,   -127);
        check_case(  -1, -128,    128);
        check_case( 128,  127,  16256);
        check_case( 128, -128, -16384);
        check_case(-127,  127, -16129);
        check_case(-127, -128,  16256);
        check_case(  37,  -19,   -703);
        check_case( -45,  -23,   1035);

        // Exhaustively check every legal centered activation and every INT8
        // weight.  Only failures are printed to keep the log readable.
        for (activation_value = -127;
             activation_value <= 128;
             activation_value = activation_value + 1) begin
            for (weight_value = -128;
                 weight_value <= 127;
                 weight_value = weight_value + 1) begin
                golden_product      = activation_value * weight_value;
                activation_centered = activation_value[8:0];
                weight_i8           = weight_value[7:0];
                #1;

                if ({{15{product[16]}}, product} !== golden_product) begin
                    $display("FAIL exhaustive: activation=%0d weight=%0d expected=%0d got=%0d",
                             activation_value, weight_value,
                             golden_product, product);
                    error_count = error_count + 1;
                end
            end
        end

        if (error_count == 0) begin
            $display("PASS exhaustive: all 65,536 legal input combinations are correct");
            $display("ALL PE MULTIPLIER TESTS PASSED");
        end else begin
            $fatal(1, "PE MULTIPLIER TEST FAILED: %0d errors", error_count);
        end

        $finish;
    end

endmodule
