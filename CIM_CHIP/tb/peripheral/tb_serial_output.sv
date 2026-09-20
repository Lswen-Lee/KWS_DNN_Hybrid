`timescale 1ns/1ps

module tb_serial_output;

    logic        bufclk = 1'b0;
    logic        reset2;
    logic        load;
    logic [17:0] parallel_data;
    logic        serial_bit;
    logic        serial_active;

    logic [17:0] expected_word;
    logic [17:0] reconstructed_word;
    integer      bit_index;
    integer      error_count;

    always #5 bufclk = ~bufclk;

    serial_output dut (
        .bufclk        (bufclk),
        .reset2        (reset2),
        .load          (load),
        .parallel_data (parallel_data),
        .serial_bit    (serial_bit),
        .serial_active (serial_active)
    );

    initial begin
        reset2            = 1'b1;
        load              = 1'b0;
        parallel_data     = 18'd0;
        expected_word     = 18'd0;
        reconstructed_word = 18'd0;
        error_count       = 0;

        $display("================================================================================");
        $display("Testbench : tb_serial_output");
        $display("Purpose   : verify one 18-bit output stage inside one lecture ACC path");
        $display("Order     : bit[17] first, followed by bit[16] down to bit[0]");
        $display("Reset     : reset2 is active-high and clears only this output stage");
        $display("================================================================================");

        // Test 1: active-high reset clears the output state.
        #1;
        if ((serial_bit !== 1'b0) || (serial_active !== 1'b0)) begin
            $display("FAIL: Test 1 - reset2 did not clear the output stage");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - reset2=1 clears serial_bit and serial_active");
        end

        @(negedge bufclk);
        reset2 = 1'b0;

        // Test 2: load 7200 and reconstruct all 18 bits MSB first.
        expected_word = 18'd7200;
        @(negedge bufclk);
        parallel_data = expected_word;
        load = 1'b1;
        @(posedge bufclk);
        #1;
        load = 1'b0;

        if ((serial_active !== 1'b1) ||
            (serial_bit !== expected_word[17])) begin
            $display("FAIL: Test 2 - bit[17] was not visible immediately after load");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - load edge immediately exposes bit[17]");
        end

        $display("\nTest 3 - serializing decimal 7200 (%018b)", expected_word);
        for (bit_index = 17; bit_index >= 0; bit_index = bit_index - 1) begin
            reconstructed_word[bit_index] = serial_bit;
            $display("  output bit %2d = %0b", bit_index, serial_bit);

            if (serial_bit !== expected_word[bit_index]) begin
                $display("FAIL: Test 3 - bit %0d expected %0b",
                         bit_index, expected_word[bit_index]);
                error_count = error_count + 1;
            end

            @(posedge bufclk);
            #1;
        end

        if ((reconstructed_word !== expected_word) ||
            (serial_active !== 1'b0) || (serial_bit !== 1'b0)) begin
            $display("FAIL: Test 3 - reconstructed=%0d, active=%0b, output=%0b",
                     reconstructed_word, serial_active, serial_bit);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - all 18 bits reconstruct 7200, then output returns low");
        end

        // Test 4: load has priority over an in-progress shift.
        @(negedge bufclk);
        parallel_data = 18'b11_0000_0000_0000_0001;
        load = 1'b1;
        @(posedge bufclk);
        #1;
        load = 1'b0;

        @(posedge bufclk);
        #1;
        if (serial_bit !== 1'b1) begin
            $display("FAIL: Test 4 - first stream did not advance to bit[16]");
            error_count = error_count + 1;
        end

        @(negedge bufclk);
        parallel_data = 18'b01_1000_0000_0000_0000;
        load = 1'b1;
        @(posedge bufclk);
        #1;
        load = 1'b0;

        if (serial_bit !== 1'b0) begin
            $display("FAIL: Test 4 - reload did not restart from the new bit[17]");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - load priority restarts the stream at new bit[17]");
        end

        @(posedge bufclk);
        #1;
        if (serial_bit !== 1'b1) begin
            $display("FAIL: Test 4 - reloaded stream did not expose new bit[16]");
            error_count = error_count + 1;
        end

        // Test 5: reset2 can clear an active stream asynchronously.
        #2;
        reset2 = 1'b1;
        #1;
        if ((serial_bit !== 1'b0) || (serial_active !== 1'b0)) begin
            $display("FAIL: Test 5 - mid-stream reset2 did not clear the stage");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - mid-stream reset2 clears the serial stage");
        end

        $display("================================================================================");
        if (error_count == 0) begin
            $display("PASS: all serial_output tests passed");
        end else begin
            $display("FAIL: %0d serial_output checks failed", error_count);
            $fatal(1);
        end
        $display("================================================================================");
        $finish;
    end

endmodule
