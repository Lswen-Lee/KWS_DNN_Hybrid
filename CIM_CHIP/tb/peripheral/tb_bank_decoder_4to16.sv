`timescale 1ns/1ps

module tb_bank_decoder_4to16;

    logic [3:0]  bank_addr;
    logic [15:0] bank_select;

    logic [15:0] expected_select;
    integer address_index;
    integer output_index;
    integer selected_count;
    integer error_count;

    bank_decoder_4to16 dut (
        .bank_addr   (bank_addr),
        .bank_select (bank_select)
    );

    initial begin
        bank_addr      = 4'b0000;
        expected_select = 16'b0;
        error_count    = 0;

        $display("============================================================");
        $display("Testbench : tb_bank_decoder_4to16");
        $display("Purpose   : convert B[3:0] into 16 active-high one-hot selects");
        $display("Mapping   : address N must assert only bank_select[N]");
        $display("Scope     : mode routing and physical bank pairing are separate");
        $display("============================================================");

        // Exhaustively verify every possible four-bit address.
        for (address_index = 0; address_index < 16; address_index = address_index + 1) begin
            bank_addr = address_index[3:0];
            #1;

            expected_select = 16'b0;
            expected_select[address_index] = 1'b1;

            selected_count = 0;
            for (output_index = 0; output_index < 16; output_index = output_index + 1) begin
                if (bank_select[output_index] === 1'b1)
                    selected_count = selected_count + 1;
            end

            $display("Address B[3:0]=%04b (%2d) -> bank_select=%04h, active outputs=%0d",
                     bank_addr, address_index, bank_select, selected_count);

            if (bank_select !== expected_select) begin
                $display("FAIL: address %0d expected=%04h, actual=%04h",
                         address_index, expected_select, bank_select);
                error_count = error_count + 1;
            end

            if (selected_count != 1) begin
                $display("FAIL: address %0d enabled %0d outputs instead of one",
                         address_index, selected_count);
                error_count = error_count + 1;
            end
        end

        // Explicit boundary checks make the bit ordering easy to inspect.
        bank_addr = 4'd0;
        #1;
        if (bank_select !== 16'h0001) begin
            $display("FAIL: address 0 did not select output o0");
            error_count = error_count + 1;
        end

        bank_addr = 4'd7;
        #1;
        if (bank_select !== 16'h0080) begin
            $display("FAIL: address 7 did not select output o7");
            error_count = error_count + 1;
        end

        bank_addr = 4'd8;
        #1;
        if (bank_select !== 16'h0100) begin
            $display("FAIL: address 8 did not select output o8");
            error_count = error_count + 1;
        end

        bank_addr = 4'd15;
        #1;
        if (bank_select !== 16'h8000) begin
            $display("FAIL: address 15 did not select output o15");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("PASS: boundary outputs o0, o7, o8 and o15 are correct");

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all 16 bank-decoder addresses are correct and one-hot");
        end else begin
            $display("FAIL: %0d bank-decoder checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
