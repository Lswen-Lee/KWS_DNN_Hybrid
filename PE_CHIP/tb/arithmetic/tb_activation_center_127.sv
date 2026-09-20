`timescale 1ns/1ps

module tb_activation_center_127;

    logic        [7:0] activation_u8;
    logic signed [8:0] activation_centered;
    logic signed [8:0] expected_centered;

    integer input_code;
    integer error_count;
    integer check_count;

    activation_center_127 dut (
        .activation_u8       (activation_u8),
        .activation_centered (activation_centered)
    );

    task automatic check_boundary;
        input integer test_input;
        input integer expected_output;
        begin
            activation_u8 = test_input[7:0];
            #1;
            expected_centered = $signed(expected_output[8:0]);
            check_count = check_count + 1;

            if (activation_centered !== expected_centered) begin
                $display("FAIL boundary %0d: input=%0d expected=%0d got=%0d",
                         check_count, test_input, expected_output,
                         activation_centered);
                error_count = error_count + 1;
            end else begin
                $display("PASS boundary %0d: UINT8 %3d -> signed %4d",
                         check_count, test_input, activation_centered);
            end
        end
    endtask

    initial begin
        activation_u8    = 8'd0;
        expected_centered = 9'sd0;
        error_count      = 0;
        check_count      = 0;

        $display("============================================================");
        $display("Testbench : tb_activation_center_127");
        $display("Equation  : activation_centered = activation_u8 - 127");
        $display("Input     : UINT8 0..255");
        $display("Output    : signed 9-bit -127..128");
        $display("============================================================");

        // Human-readable boundary and zero-point checks.
        check_boundary(0,   -127);
        check_boundary(1,   -126);
        check_boundary(126,   -1);
        check_boundary(127,    0);
        check_boundary(128,    1);
        check_boundary(254,  127);
        check_boundary(255,  128);

        // Exhaustively verify every legal UINT8 code.  Only failures are
        // printed so the simulation log remains short and readable.
        for (input_code = 0; input_code < 256; input_code = input_code + 1) begin
            activation_u8 = input_code[7:0];
            expected_centered =
                $signed({1'b0, input_code[7:0]}) - 9'sd127;
            #1;

            if (activation_centered !== expected_centered) begin
                $display("FAIL exhaustive: input=%0d expected=%0d got=%0d",
                         input_code, expected_centered,
                         activation_centered);
                error_count = error_count + 1;
            end
        end

        if (error_count == 0) begin
            $display("PASS exhaustive: all 256 UINT8 codes are correct");
            $display("ALL ACTIVATION CENTER TESTS PASSED");
        end else begin
            $fatal(1, "ACTIVATION CENTER TEST FAILED: %0d errors",
                   error_count);
        end

        $finish;
    end

endmodule
