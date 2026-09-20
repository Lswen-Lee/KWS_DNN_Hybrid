`timescale 1ns/1ps

module tb_sram_read_serializer_8bit;

    logic       clk = 1'b0;
    logic       rst_n;
    logic [3:0] even_read_data;
    logic [3:0] odd_read_data;
    logic       pair_read_valid;
    logic       serial_read_bit;

    logic [7:0] expected_word;
    logic [7:0] captured_word;
    integer     bit_index;
    integer     error_count;

    always #5 clk = ~clk;

    sram_read_serializer_8bit dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .even_read_data  (even_read_data),
        .odd_read_data   (odd_read_data),
        .pair_read_valid (pair_read_valid),
        .serial_read_bit (serial_read_bit)
    );

    initial begin
        rst_n           = 1'b0;
        even_read_data  = 4'b0000;
        odd_read_data   = 4'b0000;
        pair_read_valid = 1'b0;
        expected_word   = 8'h00;
        captured_word   = 8'h00;
        error_count     = 0;

        $display("================================================================================");
        $display("Testbench : tb_sram_read_serializer_8bit");
        $display("Purpose   : serialize two 4-bit SRAM sense results into one 8-bit word");
        $display("Mapping   : {even_read_data, odd_read_data}");
        $display("Order     : MSB first, bit 7 down to bit 0");
        $display("================================================================================");

        // Test 1: active-low reset clears the serial output.
        repeat (2) @(posedge clk);
        #1;
        if (serial_read_bit !== 1'b0) begin
            $display("FAIL: Test 1 - reset did not clear serial_read_bit");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - rst_n=0 clears the serializer");
        end

        @(negedge clk);
        rst_n = 1'b1;

        // Test 2: data without pair_valid must not load a byte.
        even_read_data  = 4'b1111;
        odd_read_data   = 4'b1111;
        pair_read_valid = 1'b0;
        @(posedge clk);
        #1;

        if (serial_read_bit !== 1'b0) begin
            $display("FAIL: Test 2 - data without pair_read_valid loaded a byte");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - pair_read_valid is required for loading");
        end

        // Test 3: reproduce the lecture SRAM read value 0x91.
        @(negedge clk);
        even_read_data  = 4'b1001;
        odd_read_data   = 4'b0001;
        pair_read_valid = 1'b1;
        @(posedge clk);
        #1;
        pair_read_valid = 1'b0;
        expected_word   = 8'h91;
        captured_word   = 8'h00;

        $display("\nTest 3 - lecture word 0x91");
        $display("  SA-equivalent data: even=%04b, odd=%04b",
                 even_read_data, odd_read_data);

        for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
            captured_word[bit_index] = serial_read_bit;
            $display("  clock bit[%0d]: serial_read_bit=%0b",
                     bit_index, serial_read_bit);

            if (serial_read_bit !== expected_word[bit_index]) begin
                $display("FAIL: Test 3 - bit[%0d] expected %0b",
                         bit_index, expected_word[bit_index]);
                error_count = error_count + 1;
            end

            @(posedge clk);
            #1;
        end

        if (captured_word !== expected_word) begin
            $display("FAIL: Test 3 - reconstructed=%02h, expected=%02h",
                     captured_word, expected_word);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - reconstructed logical read word=%02h", captured_word);
            $display("      lecture pre-PAD inverse reference=%02h", ~captured_word);
        end

        // The register shifts in zeros after all eight bits are sent.
        if (serial_read_bit !== 1'b0) begin
            $display("FAIL: Test 4 - output did not become zero after eight bits");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - zero fill leaves the output low after eight bits");
        end

        // Test 5: verify the second lecture value and nibble ordering.
        @(negedge clk);
        even_read_data  = 4'b0101;
        odd_read_data   = 4'b0010;
        pair_read_valid = 1'b1;
        @(posedge clk);
        #1;
        pair_read_valid = 1'b0;
        expected_word   = 8'h52;
        captured_word   = 8'h00;

        $display("\nTest 5 - lecture word 0x52");
        for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
            captured_word[bit_index] = serial_read_bit;
            $display("  clock bit[%0d]: serial_read_bit=%0b",
                     bit_index, serial_read_bit);
            @(posedge clk);
            #1;
        end

        if (captured_word !== expected_word) begin
            $display("FAIL: Test 5 - reconstructed=%02h, expected=%02h",
                     captured_word, expected_word);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - high/low nibble order reconstructs %02h", captured_word);
            $display("      lecture pre-PAD inverse reference=%02h", ~captured_word);
        end

        // Test 6: a new valid pair has priority over shifting an old stream.
        @(negedge clk);
        even_read_data  = 4'b1010;
        odd_read_data   = 4'b0101;
        pair_read_valid = 1'b1;
        @(posedge clk);
        #1;
        pair_read_valid = 1'b0;

        @(posedge clk);
        #1;

        @(negedge clk);
        even_read_data  = 4'b0011;
        odd_read_data   = 4'b1100;
        pair_read_valid = 1'b1;
        @(posedge clk);
        #1;
        pair_read_valid = 1'b0;

        if (serial_read_bit !== 1'b0) begin
            $display("FAIL: Test 6 - new load did not replace the old stream at bit[7]");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - a new complete SA word has priority over shifting");
        end

        // Test 7: asynchronous reset works while a serial stream is active.
        #2;
        rst_n = 1'b0;
        #1;
        if (serial_read_bit !== 1'b0) begin
            $display("FAIL: Test 7 - mid-stream reset did not clear the output");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - mid-stream reset clears the shift register");
        end

        $display("================================================================================");
        if (error_count == 0) begin
            $display("PASS: all SRAM read serializer tests passed");
        end else begin
            $display("FAIL: %0d SRAM read serializer checks failed", error_count);
            $fatal(1);
        end
        $display("================================================================================");

        $finish;
    end

endmodule
