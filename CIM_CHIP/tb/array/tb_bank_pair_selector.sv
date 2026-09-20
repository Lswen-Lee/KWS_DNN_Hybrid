`timescale 1ns/1ps

module tb_bank_pair_selector;

    logic [15:0] bank_select;
    logic        mode_sel;
    logic [15:0] cim_pair_en;
    logic [15:0] sram_pair_en;

    logic [15:0] expected_select;
    integer pair_index;
    integer output_index;
    integer active_cim_count;
    integer active_sram_count;
    integer error_count;

    bank_pair_selector dut (
        .bank_select  (bank_select),
        .mode_sel     (mode_sel),
        .cim_pair_en  (cim_pair_en),
        .sram_pair_en (sram_pair_en)
    );

    initial begin
        bank_select    = 16'b0;
        mode_sel       = 1'b0;
        expected_select = 16'b0;
        error_count    = 0;

        $display("==========================================================================");
        $display("Testbench : tb_bank_pair_selector");
        $display("Purpose   : route one of 16 adjacent 32x4 segment pairs by mode");
        $display("Pair p    : even segment=2*p, odd segment=2*p+1");
        $display("Mode      : mode_sel=0 -> SRAM, mode_sel=1 -> CIM");
        $display("Boundary  : this block does not combine the two accumulator values");
        $display("==========================================================================");

        // Test 1: no decoded bank means that both mode paths remain disabled.
        #1;
        if ((cim_pair_en !== 16'b0) || (sram_pair_en !== 16'b0)) begin
            $display("FAIL: Test 1 - zero selection enabled an output");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - zero selection disables both mode paths");
        end

        // Test 2: exhaust all sixteen pair positions in SRAM mode.
        // A selected pair p represents physical segments 2*p and 2*p+1.
        mode_sel = 1'b0;
        for (pair_index = 0; pair_index < 16; pair_index = pair_index + 1) begin
            bank_select = 16'b0;
            bank_select[pair_index] = 1'b1;
            expected_select = 16'b0;
            expected_select[pair_index] = 1'b1;
            #1;

            active_cim_count  = 0;
            active_sram_count = 0;
            for (output_index = 0; output_index < 16; output_index = output_index + 1) begin
                if (cim_pair_en[output_index] === 1'b1)
                    active_cim_count = active_cim_count + 1;
                if (sram_pair_en[output_index] === 1'b1)
                    active_sram_count = active_sram_count + 1;
            end

            $display("SRAM pair %2d -> segments %2d/%2d | sram=%04h cim=%04h",
                     pair_index, pair_index * 2, pair_index * 2 + 1,
                     sram_pair_en, cim_pair_en);

            if ((sram_pair_en !== expected_select) ||
                (cim_pair_en !== 16'b0) ||
                (active_sram_count != 1) ||
                (active_cim_count != 0)) begin
                $display("FAIL: SRAM routing at pair %0d", pair_index);
                error_count = error_count + 1;
            end
        end
        if (error_count == 0)
            $display("PASS: Test 2 - all 16 SRAM pair positions are correct");

        // Test 3: exhaust all sixteen pair positions in CIM mode.
        mode_sel = 1'b1;
        for (pair_index = 0; pair_index < 16; pair_index = pair_index + 1) begin
            bank_select = 16'b0;
            bank_select[pair_index] = 1'b1;
            expected_select = 16'b0;
            expected_select[pair_index] = 1'b1;
            #1;

            active_cim_count  = 0;
            active_sram_count = 0;
            for (output_index = 0; output_index < 16; output_index = output_index + 1) begin
                if (cim_pair_en[output_index] === 1'b1)
                    active_cim_count = active_cim_count + 1;
                if (sram_pair_en[output_index] === 1'b1)
                    active_sram_count = active_sram_count + 1;
            end

            $display("CIM  pair %2d -> segments %2d/%2d | cim=%04h sram=%04h",
                     pair_index, pair_index * 2, pair_index * 2 + 1,
                     cim_pair_en, sram_pair_en);

            if ((cim_pair_en !== expected_select) ||
                (sram_pair_en !== 16'b0) ||
                (active_cim_count != 1) ||
                (active_sram_count != 0)) begin
                $display("FAIL: CIM routing at pair %0d", pair_index);
                error_count = error_count + 1;
            end
        end
        if (error_count == 0)
            $display("PASS: Test 3 - all 16 CIM pair positions are correct");

        // Test 4: keep pair 5 selected and change only the operating mode.
        // This verifies the one-to-two demultiplexer truth table directly.
        bank_select = 16'h0020;
        mode_sel    = 1'b0;
        #1;
        if ((sram_pair_en !== 16'h0020) || (cim_pair_en !== 16'h0000)) begin
            $display("FAIL: Test 4a - pair 5 did not route to SRAM");
            error_count = error_count + 1;
        end

        mode_sel = 1'b1;
        #1;
        if ((cim_pair_en !== 16'h0020) || (sram_pair_en !== 16'h0000)) begin
            $display("FAIL: Test 4b - pair 5 did not route to CIM");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - pair 5 moves exclusively from SRAM to CIM");
        end

        // Test 5: bank_select is normally one-hot because it comes from the
        // decoder.  If upstream logic supplies multiple bits, this module is
        // deliberately a transparent router rather than a priority encoder.
        bank_select = 16'h8001;
        mode_sel    = 1'b0;
        #1;
        if ((sram_pair_en !== 16'h8001) || (cim_pair_en !== 16'h0000)) begin
            $display("FAIL: Test 5a - multi-hot SRAM input was not preserved");
            error_count = error_count + 1;
        end

        mode_sel = 1'b1;
        #1;
        if ((cim_pair_en !== 16'h8001) || (sram_pair_en !== 16'h0000)) begin
            $display("FAIL: Test 5b - multi-hot CIM input was not preserved");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - routing adds no hidden priority encoding");
        end

        // Leave all pair enables inactive at the end of simulation.
        bank_select = 16'b0;
        mode_sel    = 1'b0;
        #1;

        $display("==========================================================================");
        if (error_count == 0) begin
            $display("PASS: all bank-pair-selector tests passed");
        end else begin
            $display("FAIL: %0d bank-pair-selector checks failed", error_count);
            $fatal(1);
        end
        $display("==========================================================================");

        $finish;
    end

endmodule
