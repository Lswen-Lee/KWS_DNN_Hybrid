`timescale 1ns/1ps

module tb_row_decoder_7to128;

    logic [6:0]   row_addr;
    logic         wl_en;
    logic [127:0] wl_select;

    logic [127:0] expected_select;
    integer address_index;
    integer bit_index;
    integer selected_count;
    integer error_count;

    row_decoder_7to128 dut (
        .row_addr  (row_addr),
        .wl_en     (wl_en),
        .wl_select (wl_select)
    );

    initial begin
        row_addr       = 7'd0;
        wl_en          = 1'b0;
        expected_select = 128'b0;
        error_count    = 0;

        $display("============================================================");
        $display("Testbench : tb_row_decoder_7to128");
        $display("Purpose   : convert one 7-bit row address into 128 one-hot WLs");
        $display("Hierarchy : A[2:0] -> 3-to-8, A[6:3] -> 4-to-16");
        $display("Safety    : wl_en=0 must disable every wordline");
        $display("============================================================");

        // Test 1: no wordline may turn on while wl_en is low.
        row_addr = 7'd0;
        #1;
        if (wl_select !== 128'b0) begin
            $display("FAIL: wl_en=0 did not disable all WLs at address 0");
            error_count = error_count + 1;
        end

        row_addr = 7'd63;
        #1;
        if (wl_select !== 128'b0) begin
            $display("FAIL: wl_en=0 did not disable all WLs at address 63");
            error_count = error_count + 1;
        end

        row_addr = 7'd127;
        #1;
        if (wl_select !== 128'b0) begin
            $display("FAIL: wl_en=0 did not disable all WLs at address 127");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("PASS: Test 1 - wl_en=0 disables all 128 wordlines");

        // Test 2: verify all 128 addresses.  wl_en is lowered before every
        // address change, matching the safe sequence required by the decoder.
        for (address_index = 0; address_index < 128; address_index = address_index + 1) begin
            wl_en = 1'b0;
            #1;

            row_addr = address_index[6:0];
            #1;
            if (wl_select !== 128'b0) begin
                $display("FAIL: address %0d changed while wl_en=0 but a WL turned on",
                         address_index);
                error_count = error_count + 1;
            end

            wl_en = 1'b1;
            #1;

            expected_select = 128'b0;
            expected_select[address_index] = 1'b1;

            if (wl_select !== expected_select) begin
                $display("FAIL: address %0d selected the wrong wordline", address_index);
                $display("      expected=%032h", expected_select);
                $display("      actual  =%032h", wl_select);
                error_count = error_count + 1;
            end

            // Count active outputs without relying on advanced assertion
            // functions, so the one-hot check remains easy to understand.
            selected_count = 0;
            for (bit_index = 0; bit_index < 128; bit_index = bit_index + 1) begin
                if (wl_select[bit_index] === 1'b1)
                    selected_count = selected_count + 1;
            end

            if (selected_count != 1) begin
                $display("FAIL: address %0d enabled %0d wordlines instead of one",
                         address_index, selected_count);
                error_count = error_count + 1;
            end
        end

        if (error_count == 0)
            $display("PASS: Test 2 - addresses 0 through 127 are all one-hot");

        // Test 3: explicitly show the boundaries relevant to the hierarchy.
        // Address 7 -> 8 crosses a 3-to-8 local-row boundary.
        row_addr = 7'd7;
        #1;
        if (wl_select[7] !== 1'b1) begin
            $display("FAIL: boundary address 7 did not select WL7");
            error_count = error_count + 1;
        end

        wl_en = 1'b0;
        row_addr = 7'd8;
        #1;
        wl_en = 1'b1;
        #1;
        if (wl_select[8] !== 1'b1) begin
            $display("FAIL: boundary address 8 did not select WL8");
            error_count = error_count + 1;
        end

        // Address 31 -> 32 crosses from one 32-row CIM group to the next.
        wl_en = 1'b0;
        row_addr = 7'd31;
        #1;
        wl_en = 1'b1;
        #1;
        if (wl_select[31] !== 1'b1) begin
            $display("FAIL: group boundary address 31 did not select WL31");
            error_count = error_count + 1;
        end

        wl_en = 1'b0;
        row_addr = 7'd32;
        #1;
        wl_en = 1'b1;
        #1;
        if (wl_select[32] !== 1'b1) begin
            $display("FAIL: group boundary address 32 did not select WL32");
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("PASS: Test 3 - decoder and 32-row group boundaries are correct");

        // Leave the decoder in its safe disabled state.
        wl_en = 1'b0;
        #1;

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all row-decoder tests passed");
        end else begin
            $display("FAIL: %0d row-decoder checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
