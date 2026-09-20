`timescale 1ns/1ps

module tb_bitserial_accumulator;

    logic        bufclk = 1'b0;
    logic        reset1;
    logic        reset2;
    logic        output_en;
    logic [8:0]  partial_sum;
    logic [17:0] accumulated_sum;
    logic        serial_sum;
    logic        serial_active;

    logic [17:0] reconstructed_sum;
    integer      sample_number;
    integer      bit_index;
    integer      error_count;

    always #5 bufclk = ~bufclk;

    bitserial_accumulator dut (
        .bufclk          (bufclk),
        .reset1          (reset1),
        .reset2          (reset2),
        .output_en       (output_en),
        .partial_sum     (partial_sum),
        .accumulated_sum (accumulated_sum),
        .serial_sum      (serial_sum),
        .serial_active   (serial_active)
    );

    task automatic reset_acc_and_output;
        begin
            @(negedge bufclk);
            output_en   = 1'b0;
            partial_sum = 9'd0;
            reset1      = 1'b1;
            reset2      = 1'b1;
            #1;

            if ((accumulated_sum !== 18'd0) ||
                (serial_sum !== 1'b0) || (serial_active !== 1'b0)) begin
                $display("FAIL: reset1/reset2 did not clear both states");
                error_count = error_count + 1;
            end

            @(negedge bufclk);
            reset1 = 1'b0;
            reset2 = 1'b0;
        end
    endtask

    task automatic apply_sample(
        input logic [8:0]  sample_value,
        input logic [17:0] expected_sum
    );
        begin
            @(negedge bufclk);
            partial_sum = sample_value;
            output_en   = 1'b1;
            @(posedge bufclk);
            #1;
            output_en = 1'b0;
            sample_number = sample_number + 1;

            $display("  sample %0d: partial=%3d -> accumulator=%6d",
                     sample_number, sample_value, accumulated_sum);

            if (accumulated_sum !== expected_sum) begin
                $display("FAIL: expected accumulator=%0d", expected_sum);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        reset1           = 1'b1;
        reset2           = 1'b1;
        output_en        = 1'b0;
        partial_sum      = 9'd0;
        reconstructed_sum = 18'd0;
        sample_number    = 0;
        error_count      = 0;

        $display("================================================================================");
        $display("Testbench : tb_bitserial_accumulator");
        $display("Equation  : ACC_next = (ACC << 1) + partial_sum");
        $display("Sequence  : exactly 8 accepted UINT8 bit planes, MSB first");
        $display("Output    : 18-bit serial stream starts at bit[17] on sample 8");
        $display("Reset     : reset1=ACC state, reset2=serial state, both active-high");
        $display("================================================================================");

        // Test 1: both active-high reset domains start at zero.
        #1;
        if ((accumulated_sum !== 18'd0) ||
            (serial_sum !== 1'b0) || (serial_active !== 1'b0)) begin
            $display("FAIL: Test 1 - initial reset state is not zero");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - reset1/reset2 clear their respective states");
        end

        @(negedge bufclk);
        reset1 = 1'b0;
        reset2 = 1'b0;

        // Test 2: output_en=0 must hold the accumulator.
        partial_sum = 9'd480;
        repeat (2) @(posedge bufclk);
        #1;
        if (accumulated_sum !== 18'd0) begin
            $display("FAIL: Test 2 - output_en=0 changed the accumulator");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - output_en=0 holds the accumulator");
        end

        // Test 3: lecture example 32 x weight 15 x activation 15 = 7200.
        // Activation 8'h0f is supplied as 00001111 from bit7 to bit0.
        $display("\nTest 3 - lecture example, expected result 7200");
        reset_acc_and_output();
        sample_number = 0;
        apply_sample(9'd0,   18'd0);
        apply_sample(9'd0,   18'd0);
        apply_sample(9'd0,   18'd0);
        apply_sample(9'd0,   18'd0);
        apply_sample(9'd480, 18'd480);
        apply_sample(9'd480, 18'd1440);
        apply_sample(9'd480, 18'd3360);
        apply_sample(9'd480, 18'd7200);

        if ((serial_active !== 1'b1) ||
            (serial_sum !== 1'b0)) begin
            $display("FAIL: Test 3 - sample 8 did not immediately expose bit[17]");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - sample 8 immediately exposes result bit[17]");
        end

        reconstructed_sum = 18'd0;
        for (bit_index = 17; bit_index >= 0; bit_index = bit_index - 1) begin
            reconstructed_sum[bit_index] = serial_sum;
            $display("  serial bit %2d = %0b", bit_index, serial_sum);
            @(posedge bufclk);
            #1;
        end

        if ((reconstructed_sum !== 18'd7200) ||
            (serial_active !== 1'b0)) begin
            $display("FAIL: Test 3 - reconstructed serial result=%0d",
                     reconstructed_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - serial output reconstructs decimal 7200");
        end

        // Test 4: after eight accepted samples, a ninth output_en is ignored
        // until reset1 starts the next operation.
        @(negedge bufclk);
        partial_sum = 9'd511;
        output_en = 1'b1;
        @(posedge bufclk);
        #1;
        output_en = 1'b0;
        if (accumulated_sum !== 18'd7200) begin
            $display("FAIL: Test 4 - ninth sample changed the completed result");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - internal count prevents a ninth accumulation");
        end

        // Test 5: maximum one-bank result still fits the 18-bit output.
        $display("\nTest 5 - maximum 32 x 15 x 255 = 122400");
        reset_acc_and_output();
        sample_number = 0;
        apply_sample(9'd480, 18'd480);
        apply_sample(9'd480, 18'd1440);
        apply_sample(9'd480, 18'd3360);
        apply_sample(9'd480, 18'd7200);
        apply_sample(9'd480, 18'd14880);
        apply_sample(9'd480, 18'd30240);
        apply_sample(9'd480, 18'd60960);
        apply_sample(9'd480, 18'd122400);
        if (accumulated_sum !== 18'd122400) begin
            $display("FAIL: Test 5 - maximum result is incorrect");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - maximum result 122400 fits in 18 bits");
        end

        // Test 6: disabled clocks do not shift or consume one of the 8 slots.
        $display("\nTest 6 - output_en gaps do not consume samples");
        reset_acc_and_output();
        sample_number = 0;
        apply_sample(9'd1, 18'd1);
        @(negedge bufclk);
        output_en = 1'b0;
        partial_sum = 9'd480;
        repeat (2) @(posedge bufclk);
        #1;
        if (accumulated_sum !== 18'd1) begin
            $display("FAIL: Test 6 - a disabled clock changed the result");
            error_count = error_count + 1;
        end
        apply_sample(9'd1, 18'd3);
        apply_sample(9'd1, 18'd7);
        apply_sample(9'd1, 18'd15);
        apply_sample(9'd1, 18'd31);
        apply_sample(9'd1, 18'd63);
        apply_sample(9'd1, 18'd127);
        apply_sample(9'd1, 18'd255);
        if (accumulated_sum !== 18'd255) begin
            $display("FAIL: Test 6 - eight accepted ones should produce 255");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - only enabled edges consume a sample");
        end

        // Test 7: reset1 and reset2 control separate state domains.
        $display("\nTest 7 - reset1/reset2 independence");
        #2;
        reset1 = 1'b1;
        #1;
        if ((accumulated_sum !== 18'd0) || (serial_active !== 1'b1)) begin
            $display("FAIL: Test 7 - reset1 did not clear only accumulator state");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - reset1 clears ACC while serial stream remains active");
        end

        reset1 = 1'b0;
        sample_number = 0;
        apply_sample(9'd9, 18'd9);

        reset2 = 1'b1;
        #1;
        if ((serial_sum !== 1'b0) || (serial_active !== 1'b0) ||
            (accumulated_sum !== 18'd9)) begin
            $display("FAIL: Test 7 - reset2 did not clear only serial state");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - reset2 clears serial state while ACC remains 9");
        end

        $display("================================================================================");
        if (error_count == 0) begin
            $display("PASS: all integrated accumulator/output tests passed");
        end else begin
            $display("FAIL: %0d accumulator/output checks failed", error_count);
            $fatal(1);
        end
        $display("================================================================================");
        $finish;
    end

endmodule
