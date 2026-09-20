`timescale 1ns/1ps

module tb_dcim_bank_32x4;

    logic        clk = 1'b0;
    logic        rst_n;
    logic [31:0] row_write_en;
    logic [3:0]  write_data;
    logic        sense_en;
    logic [31:0] row_read_en;
    logic [3:0]  read_data;
    logic        read_valid;
    logic        nv_store;
    logic        nv_recall;
    logic        pd_en;
    logic        cim_en;
    logic        cim_row;
    logic [31:0] activation_bits;
    logic [3:0]  row_product [0:31];
    // Reference-only reduction: the DUT no longer owns an adder tree.
    logic [8:0]  bank_sum;

    integer i;
    integer error_count;
    integer one_hot_error_count;
    integer readback_error_count;

    always #5 clk = ~clk;

    dcim_bank_32x4 dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .row_write_en    (row_write_en),
        .write_data      (write_data),
        .sense_en        (sense_en),
        .row_read_en     (row_read_en),
        .read_data       (read_data),
        .read_valid      (read_valid),
        .nv_store        (nv_store),
        .nv_recall       (nv_recall),
        .pd_en           (pd_en),
        .cim_en          (cim_en),
        .cim_row         (cim_row),
        .activation_bits (activation_bits),
        .row_product     (row_product)
    );

    integer sum_index;
    always_comb begin
        bank_sum = 9'b0;
        for (sum_index = 0; sum_index < 32; sum_index = sum_index + 1)
            bank_sum = bank_sum + {5'b0, row_product[sum_index]};
    end

    initial begin
        rst_n              = 1'b0;
        row_write_en       = 32'b0;
        write_data         = 4'b0;
        sense_en           = 1'b0;
        row_read_en        = 32'b0;
        nv_store           = 1'b0;
        nv_recall          = 1'b0;
        pd_en              = 1'b0;
        cim_en             = 1'b1;
        cim_row            = 1'b1;
        activation_bits    = 32'hffff_ffff;
        error_count        = 0;
        one_hot_error_count = 0;
        readback_error_count = 0;

        $display("============================================================");
        $display("Testbench : tb_dcim_bank_32x4");
        $display("Structure : 32 rows x 4-bit weight; no local adder tree");
        $display("Equation  : TB reference sum = sum(row_product[i])");
        $display("Maximum   : 32 x 15 = 480");
        $display("Read path : combinational SA-equivalent output; serializer owns the register");
        $display("============================================================");

        // Test 1: reset clears every stored weight.
        repeat (2) @(posedge clk);
        #1;
        $display("Test 1 - reset clears all rows       : expected=0,   actual=%0d", bank_sum);
        if (bank_sum !== 9'd0) begin
            $display("FAIL: Test 1");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1");
        end
        rst_n = 1'b1;

        // Program row 0..31 with values 0..15 repeated twice.
        $display("\nWrite pattern: row 0..31 receives weight 0..15 repeated twice");
        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            row_write_en    = 32'b0;
            row_write_en[i] = 1'b1;
            write_data      = i[3:0];
            @(posedge clk);
            #1;
        end
        row_write_en = 32'b0;

        // The Bank itself must not add a read register.  Once sense_en and the
        // one-hot row are valid, weight 15 is visible before the next clock;
        // the downstream serializer will capture it at that next rising edge.
        sense_en       = 1'b1;
        row_read_en    = 32'b0;
        row_read_en[15] = 1'b1;
        #1;
        if ((read_valid !== 1'b1) || (read_data !== 4'd15)) begin
            $display("FAIL: combinational read expected=15, actual=%0d, valid=%b",
                     read_data, read_valid);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Bank data is ready before the serializer capture edge");
        end

        // A clock edge must not introduce a second Bank-level latency.
        @(posedge clk);
        #1;
        if ((read_valid !== 1'b1) || (read_data !== 4'd15)) begin
            $display("FAIL: read changed across clock, expected=15, actual=%0d, valid=%b",
                     read_data, read_valid);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Bank read remains combinational across the clock edge");
        end

        // Directly read every programmed row.  The expected values are 0..15
        // repeated twice, matching the write pattern above.
        readback_error_count = 0;
        for (i = 0; i < 32; i = i + 1) begin
            row_read_en    = 32'b0;
            row_read_en[i] = 1'b1;
            #1;
            if ((read_valid !== 1'b1) || (read_data !== i[3:0])) begin
                $display("FAIL: read row %0d, expected=%0d, actual=%0d, valid=%b",
                         i, i[3:0], read_data, read_valid);
                readback_error_count = readback_error_count + 1;
            end
        end
        if (readback_error_count == 0) begin
            $display("PASS: direct readback of all 32 programmed rows");
        end else begin
            error_count = error_count + readback_error_count;
        end

        // A disabled sense request clears valid and data without another edge.
        @(negedge clk);
        sense_en   = 1'b0;
        row_read_en = 32'h0000_8000;
        #1;
        if ((read_valid !== 1'b0) || (read_data !== 4'b0000)) begin
            $display("FAIL: disabled read, data=%04b valid=%b", read_data, read_valid);
            error_count = error_count + 1;
        end else begin
            $display("PASS: disabled read immediately outputs data=0 and valid=0");
        end

        // sense_en without a selected row is also invalid.
        @(negedge clk);
        sense_en   = 1'b1;
        row_read_en = 32'b0;
        #1;
        if ((read_valid !== 1'b0) || (read_data !== 4'b0000)) begin
            $display("FAIL: empty read selection, data=%04b valid=%b", read_data, read_valid);
            error_count = error_count + 1;
        end else begin
            $display("PASS: no selected row outputs data=0 and valid=0");
        end
        sense_en = 1'b0;

        // Test 2: all activations select all 32 programmed weights.
        activation_bits = 32'hffff_ffff;
        #1;
        $display("Test 2 - all activations enabled     : expected=240, actual=%0d", bank_sum);
        if (bank_sum !== 9'd240) begin
            $display("FAIL: Test 2");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2");
        end

        // Test 3: select only row 15, whose stored weight is 15.
        activation_bits     = 32'b0;
        activation_bits[15] = 1'b1;
        #1;
        $display("Test 3 - only row 15 active          : expected=15,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd15) begin
            $display("FAIL: Test 3");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3");
        end

        // Test 4: row 31 is in the upper half and also stores weight 15.
        activation_bits     = 32'b0;
        activation_bits[31] = 1'b1;
        #1;
        $display("Test 4 - only row 31 active          : expected=15,  actual=%0d", bank_sum);
        if (bank_sum !== 9'd15) begin
            $display("FAIL: Test 4");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4");
        end

        // Test 5: activate only even row numbers.
        activation_bits = 32'b0;
        for (i = 0; i < 32; i = i + 2)
            activation_bits[i] = 1'b1;
        #1;
        $display("Test 5 - even rows active            : expected=112, actual=%0d", bank_sum);
        if (bank_sum !== 9'd112) begin
            $display("FAIL: Test 5");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5");
        end

        // Test 6: activate only odd row numbers.
        activation_bits = 32'b0;
        for (i = 1; i < 32; i = i + 2)
            activation_bits[i] = 1'b1;
        #1;
        $display("Test 6 - odd rows active             : expected=128, actual=%0d", bank_sum);
        if (bank_sum !== 9'd128) begin
            $display("FAIL: Test 6");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6");
        end

        // Test 7: cim_en disables every row product.
        activation_bits = 32'hffff_ffff;
        cim_en          = 1'b0;
        #1;
        $display("Test 7 - cim_en is 0                : expected=0,   actual=%0d", bank_sum);
        if (bank_sum !== 9'd0) begin
            $display("FAIL: Test 7");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7");
        end

        // Test 8: cim_row disables the whole 32-row group.
        cim_en  = 1'b1;
        cim_row = 1'b0;
        #1;
        $display("Test 8 - cim_row is 0               : expected=0,   actual=%0d", bank_sum);
        if (bank_sum !== 9'd0) begin
            $display("FAIL: Test 8");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 8");
        end
        cim_row = 1'b1;

        // Overwrite only row 31: its weight changes from 15 to 7.
        @(negedge clk);
        row_write_en     = 32'b0;
        row_write_en[31] = 1'b1;
        write_data       = 4'd7;
        @(posedge clk);
        #1;
        row_write_en = 32'b0;

        // Direct readback confirms that only row 31 changed to seven.
        @(negedge clk);
        sense_en        = 1'b1;
        row_read_en     = 32'b0;
        row_read_en[31] = 1'b1;
        @(posedge clk);
        #1;
        if ((read_valid !== 1'b1) || (read_data !== 4'd7)) begin
            $display("FAIL: row 31 direct read, expected=7, actual=%0d", read_data);
            error_count = error_count + 1;
        end else begin
            $display("PASS: row 31 direct read after overwrite = 7");
        end
        sense_en    = 1'b0;
        row_read_en = 32'b0;

        // Test 9: the selected row changed, while other rows did not.
        activation_bits     = 32'b0;
        activation_bits[31] = 1'b1;
        #1;
        $display("Test 9 - overwrite row 31 with 7     : expected=7,   actual=%0d", bank_sum);
        if (bank_sum !== 9'd7) begin
            $display("FAIL: Test 9");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 9");
        end

        activation_bits = 32'hffff_ffff;
        #1;
        $display("Test 10 - all rows after overwrite   : expected=232, actual=%0d", bank_sum);
        if (bank_sum !== 9'd232) begin
            $display("FAIL: Test 10");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 10");
        end

        // Program every row with the maximum four-bit weight.
        $display("\nWrite maximum pattern: every row receives weight 15");
        for (i = 0; i < 32; i = i + 1) begin
            @(negedge clk);
            row_write_en    = 32'b0;
            row_write_en[i] = 1'b1;
            write_data      = 4'd15;
            @(posedge clk);
            #1;
        end
        row_write_en   = 32'b0;
        activation_bits = 32'hffff_ffff;
        #1;

        // Test 11: maximum result from the presentation and proposal.
        $display("Test 11 - 32 rows x weight 15       : expected=480, actual=%0d", bank_sum);
        if (bank_sum !== 9'd480) begin
            $display("FAIL: Test 11");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 11");
        end

        // Test 12: select each activation wire individually.  Since every
        // weight is 15, every one-hot selection must produce 15.
        one_hot_error_count = 0;
        for (i = 0; i < 32; i = i + 1) begin
            activation_bits    = 32'b0;
            activation_bits[i] = 1'b1;
            #1;
            if (bank_sum !== 9'd15) begin
                $display("FAIL: Test 12 at activation row %0d, actual=%0d",
                         i, bank_sum);
                one_hot_error_count = one_hot_error_count + 1;
            end
        end
        if (one_hot_error_count == 0) begin
            $display("PASS: Test 12 - all 32 one-hot activation wires");
        end else begin
            error_count = error_count + one_hot_error_count;
        end

        // Test 13: disabled write and reserved controls must hold all weights.
        activation_bits = 32'hffff_ffff;
        @(negedge clk);
        row_write_en = 32'b0;
        write_data   = 4'd0;
        nv_store     = 1'b1;
        nv_recall    = 1'b1;
        pd_en        = 1'b1;
        @(posedge clk);
        #1;
        $display("Test 13 - write disabled holds data  : expected=480, actual=%0d", bank_sum);
        if (bank_sum !== 9'd480) begin
            $display("FAIL: Test 13");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 13");
        end

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all dcim_bank_32x4 tests passed");
        end else begin
            $display("FAIL: %0d bank checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
