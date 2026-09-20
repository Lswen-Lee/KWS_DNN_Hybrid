`timescale 1ns/1ps

module tb_pe_accumulator_s32;

    logic               clk;
    logic               rst;
    logic               clear;
    logic               accumulate_en;
    logic signed [16:0] product;
    logic signed [31:0] accumulator;
    logic signed [31:0] expected_accumulator;

    integer cycle_index;
    integer check_count;
    integer error_count;

    pe_accumulator_s32 dut (
        .clk           (clk),
        .rst           (rst),
        .clear         (clear),
        .accumulate_en (accumulate_en),
        .product       (product),
        .accumulator   (accumulator)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic wait_rising_edge;
        begin
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_value;
        input integer expected_value;
        begin
            expected_accumulator = expected_value[31:0];
            check_count = check_count + 1;

            if (accumulator !== expected_accumulator) begin
                $display("FAIL check %0d: expected=%0d got=%0d",
                         check_count, expected_value, accumulator);
                error_count = error_count + 1;
            end else begin
                $display("PASS check %0d: accumulator=%0d",
                         check_count, accumulator);
            end
        end
    endtask

    task automatic apply_cycle;
        input logic               test_clear;
        input logic               test_enable;
        input logic signed [16:0] test_product;
        input integer expected_value;
        begin
            @(negedge clk);
            clear         = test_clear;
            accumulate_en = test_enable;
            product       = test_product;
            wait_rising_edge();
            check_value(expected_value);
        end
    endtask

    initial begin
        rst                  = 1'b1;
        clear                = 1'b0;
        accumulate_en        = 1'b0;
        product              = 17'sd0;
        expected_accumulator = 32'sd0;
        check_count          = 0;
        error_count          = 0;

        $display("============================================================");
        $display("Testbench : tb_pe_accumulator_s32");
        $display("Equation  : accumulator += sign_extend(product)");
        $display("Priority  : rst > clear > accumulate_en > hold");
        $display("Reset     : synchronous active-high");
        $display("============================================================");

        // Test 1: synchronous active-high reset initializes the register.
        wait_rising_edge();
        check_value(0);

        @(negedge clk);
        rst = 1'b0;

        // Test 2: clear wins even when accumulate_en is also asserted.
        $display("TEST: clear priority over accumulation");
        apply_cycle(1, 1, 100, 0);

        // Test 3: positive, negative and alternating accumulation.
        $display("TEST: signed accumulation");
        apply_cycle(0, 1,  100, 100);
        apply_cycle(0, 1,  -30,  70);
        apply_cycle(0, 1,  -20,  50);
        apply_cycle(0, 1,   75, 125);

        // Test 4: disabled accumulator must hold even if product changes.
        $display("TEST: enable=0 holds the previous value");
        apply_cycle(0, 0, 16256, 125);
        apply_cycle(0, 0, -16384, 125);

        // Test 5: legal positive and negative product extrema are preserved.
        $display("TEST: signed 17-bit boundary products");
        apply_cycle(1, 0,      0,     0);
        apply_cycle(0, 1,  16256, 16256);
        apply_cycle(0, 1, -16384,  -128);

        // Test 6: 144 maximum positive products model the longest FC1 K loop.
        // Only the final value is printed so the simulation log stays short.
        $display("TEST: FC1-length positive accumulation, K=144");
        apply_cycle(1, 0, 0, 0);
        for (cycle_index = 0; cycle_index < 144;
             cycle_index = cycle_index + 1) begin
            @(negedge clk);
            clear         = 1'b0;
            accumulate_en = 1'b1;
            product       = 17'sd16256;
            wait_rising_edge();
        end
        check_value(2340864);

        // Test 7: repeat the longest K loop with the most negative product.
        $display("TEST: FC1-length negative accumulation, K=144");
        apply_cycle(1, 0, 0, 0);
        for (cycle_index = 0; cycle_index < 144;
             cycle_index = cycle_index + 1) begin
            @(negedge clk);
            clear         = 1'b0;
            accumulate_en = 1'b1;
            product       = -17'sd16384;
            wait_rising_edge();
        end
        check_value(-2359296);

        // Test 8: reset is synchronous.  Merely raising rst does not change
        // the register until the next rising clock edge.
        $display("TEST: reset changes state only at a rising edge");
        apply_cycle(1, 0, 0, 0);
        apply_cycle(0, 1, 1234, 1234);
        @(negedge clk);
        rst = 1'b1;
        #1;
        check_value(1234);
        wait_rising_edge();
        check_value(0);

        @(negedge clk);
        rst           = 1'b0;
        clear         = 1'b0;
        accumulate_en = 1'b0;
        product       = 17'sd0;

        if (error_count == 0) begin
            $display("ALL PE ACCUMULATOR TESTS PASSED: %0d checks",
                     check_count);
        end else begin
            $fatal(1, "PE ACCUMULATOR TEST FAILED: %0d errors",
                   error_count);
        end

        $finish;
    end

endmodule
