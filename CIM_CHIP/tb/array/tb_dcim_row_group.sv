`timescale 1ns/1ps

module tb_dcim_row_group;

    logic        clk = 1'b0;
    logic        rst_n;
    logic [31:0] local_wl_select;
    logic        write_en;
    logic        sense_en;
    logic [15:0] sram_pair_en;
    logic [15:0] cim_pair_en;
    logic [3:0]  even_write_data;
    logic [3:0]  odd_write_data;
    logic        cim_group_en;
    logic [31:0] activation_bits;
    logic        nv_store;
    logic        nv_recall;
    logic        pd_en;
    logic [3:0]  selected_even_read_data;
    logic [3:0]  selected_odd_read_data;
    logic        selected_pair_read_valid;
    logic [3:0]  selected_even_product [0:31];
    logic [3:0]  selected_odd_product  [0:31];
    logic [8:0]  selected_even_sum;
    logic [8:0]  selected_odd_sum;

    integer bank_index;
    integer row_index;
    integer error_count;

    always #5 clk = ~clk;

    dcim_row_group dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .local_wl_select (local_wl_select),
        .write_en        (write_en),
        .sense_en        (sense_en),
        .sram_pair_en    (sram_pair_en),
        .cim_pair_en     (cim_pair_en),
        .even_write_data (even_write_data),
        .odd_write_data  (odd_write_data),
        .cim_group_en    (cim_group_en),
        .activation_bits (activation_bits),
        .nv_store        (nv_store),
        .nv_recall       (nv_recall),
        .pd_en           (pd_en),
        .selected_even_read_data(selected_even_read_data),
        .selected_odd_read_data (selected_odd_read_data),
        .selected_pair_read_valid(selected_pair_read_valid),
        .selected_even_product  (selected_even_product),
        .selected_odd_product   (selected_odd_product)
    );

    // Testbench-only reference sums verify the vectors that will be consumed
    // by the two shared array-level adder trees.
    integer product_sum_index;
    always_comb begin
        selected_even_sum = 9'b0;
        selected_odd_sum  = 9'b0;
        for (product_sum_index = 0; product_sum_index < 32;
             product_sum_index = product_sum_index + 1) begin
            selected_even_sum = selected_even_sum +
                {5'b0, selected_even_product[product_sum_index]};
            selected_odd_sum = selected_odd_sum +
                {5'b0, selected_odd_product[product_sum_index]};
        end
    end

    // Write one eight-bit word into one row of one adjacent segment pair.
    task automatic write_pair_row(
        input integer pair_number,
        input integer row_number,
        input logic [3:0] even_value,
        input logic [3:0] odd_value
    );
        begin
            @(negedge clk);
            local_wl_select             = 32'b0;
            local_wl_select[row_number] = 1'b1;
            sram_pair_en                = 16'b0;
            sram_pair_en[pair_number]   = 1'b1;
            cim_pair_en                 = 16'b0;
            even_write_data             = even_value;
            odd_write_data              = odd_value;
            write_en                    = 1'b1;
            sense_en                    = 1'b0;

            @(posedge clk);
            #1;
            $display("  write pair %0d -> segments %0d/%0d, row %0d, even=%0h odd=%0h",
                     pair_number, pair_number * 2, pair_number * 2 + 1,
                     row_number, even_value, odd_value);

            @(negedge clk);
            write_en        = 1'b0;
            local_wl_select = 32'b0;
            sram_pair_en    = 16'b0;
        end
    endtask

    // Read and check both four-bit segments belonging to one pair.
    task automatic check_pair_read(
        input integer pair_number,
        input integer row_number,
        input logic [3:0] expected_even,
        input logic [3:0] expected_odd
    );
        begin
            @(negedge clk);
            local_wl_select             = 32'b0;
            local_wl_select[row_number] = 1'b1;
            sram_pair_en                = 16'b0;
            sram_pair_en[pair_number]   = 1'b1;
            write_en                    = 1'b0;
            sense_en                    = 1'b1;

            @(posedge clk);
            #1;

            if ((selected_pair_read_valid !== 1'b1) ||
                (selected_even_read_data !== expected_even) ||
                (selected_odd_read_data !== expected_odd)) begin
                $display("FAIL: read pair %0d row %0d expected E/O=%0h/%0h, actual=%0h/%0h, pair_valid=%b",
                         pair_number, row_number, expected_even, expected_odd,
                         selected_even_read_data, selected_odd_read_data,
                         selected_pair_read_valid);
                error_count = error_count + 1;
            end else begin
                $display("  read  pair %0d <- segments %0d/%0d, row %0d, even=%0h odd=%0h : PASS",
                         pair_number, pair_number * 2, pair_number * 2 + 1,
                         row_number,
                         selected_even_read_data, selected_odd_read_data);
            end

            @(negedge clk);
            sense_en        = 1'b0;
            local_wl_select = 32'b0;
            sram_pair_en    = 16'b0;
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        rst_n            = 1'b0;
        local_wl_select  = 32'b0;
        write_en         = 1'b0;
        sense_en         = 1'b0;
        sram_pair_en     = 16'b0;
        cim_pair_en      = 16'b0;
        even_write_data  = 4'b0;
        odd_write_data   = 4'b0;
        cim_group_en     = 1'b0;
        activation_bits  = 32'b0;
        nv_store         = 1'b0;
        nv_recall        = 1'b0;
        pd_en            = 1'b0;
        error_count      = 0;

        $display("====================================================================");
        $display("Testbench : tb_dcim_row_group");
        $display("Reference : 0622.pptx slides 2, 4, 5 and 6");
        $display("Structure : 32 local rows x 32 segments x 4 columns = 32x128");
        $display("Pair p    : even segment=2p, odd segment=2p+1");
        $display("Outputs   : selected Even/Odd vectors, 32 rows x 4 bits");
        $display("====================================================================");

        // Test 1: reset reaches all 4096 storage cells.  With sense disabled,
        // every combinational read output, selected product and valid is zero.
        repeat (2) @(posedge clk);
        #1;
        if ((selected_pair_read_valid !== 1'b0) ||
            (selected_even_read_data !== 4'b0) ||
            (selected_odd_read_data !== 4'b0) ||
            (selected_even_sum !== 9'b0) ||
            (selected_odd_sum !== 9'b0)) begin
            $display("FAIL: reset left selected read or CIM outputs nonzero");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - reset clears all 32 segments");
        end
        rst_n = 1'b1;

        // Test 2: program the first pair boundary and read both nibbles back.
        $display("\nTest 2 - SRAM write/read at pair 0 boundary");
        write_pair_row(0, 0, 4'h3, 4'hc);
        check_pair_read(0, 0, 4'h3, 4'hc);

        // Test 3: program the final pair boundary.  Reading pair 0 again proves
        // that pair 15 did not overwrite another column location.
        $display("\nTest 3 - SRAM write/read at pair 15 boundary and pair isolation");
        write_pair_row(15, 31, 4'h5, 4'ha);
        check_pair_read(15, 31, 4'h5, 4'ha);
        check_pair_read(0, 0, 4'h3, 4'hc);

        // Test 4: only pair 0 and this row group are enabled for CIM.  A single
        // active row therefore returns the two stored nibbles as partial sums.
        $display("\nTest 4 - CIM pair 0, activation row 0 only");
        cim_group_en       = 1'b1;
        cim_pair_en        = 16'b0;
        cim_pair_en[0]     = 1'b1;
        activation_bits    = 32'b0;
        activation_bits[0] = 1'b1;
        #1;

        if ((selected_even_sum !== 9'd3) ||
            (selected_odd_sum !== 9'd12)) begin
            $display("FAIL: pair 0 CIM expected E/O=3/12, actual=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - pair 0 outputs remain independent (3 and 12)");
        end

        // Test 5: group selection is a separate NAND input from pair selection.
        cim_group_en = 1'b0;
        #1;
        if ((selected_even_sum !== 9'd0) ||
            (selected_odd_sum !== 9'd0)) begin
            $display("FAIL: disabled row group left CIM output E/O=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - cim_group_en=0 forces all bank sums to zero");
        end

        // Test 6: last pair and last local-row boundaries.
        cim_group_en        = 1'b1;
        cim_pair_en         = 16'b0;
        cim_pair_en[15]     = 1'b1;
        activation_bits     = 32'b0;
        activation_bits[31] = 1'b1;
        #1;
        if ((selected_even_sum !== 9'd5) ||
            (selected_odd_sum !== 9'd10)) begin
            $display("FAIL: pair 15 expected E/O=5/10, actual=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - pair 15 and local row 31 boundaries are correct");
        end

        // Test 7: zero activation must make every multiplication result zero.
        activation_bits = 32'b0;
        #1;
        if ((selected_even_sum !== 9'd0) ||
            (selected_odd_sum !== 9'd0)) begin
            $display("FAIL: zero activation left E/O=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 7 - zero activation produces zero in all segments");
        end

        // Test 8: a CIM pair enable must never open the SRAM write path.
        $display("\nTest 8 - CIM/SRAM mode isolation");
        @(negedge clk);
        local_wl_select    = 32'b0;
        local_wl_select[7] = 1'b1;
        sram_pair_en       = 16'b0;
        cim_pair_en        = 16'b0;
        cim_pair_en[5]     = 1'b1;
        even_write_data    = 4'hf;
        odd_write_data     = 4'hf;
        write_en           = 1'b1;
        @(posedge clk);
        #1;
        @(negedge clk);
        write_en           = 1'b0;
        cim_pair_en        = 16'b0;
        local_wl_select    = 32'b0;
        check_pair_read(5, 7, 4'h0, 4'h0);
        $display("PASS: Test 8 - cim_pair_en alone cannot write SRAM cells");

        // Test 9: sram_pair_en alone must not enable the CIM NAND path.
        sram_pair_en      = 16'b0;
        sram_pair_en[0]   = 1'b1;
        cim_pair_en       = 16'b0;
        cim_group_en      = 1'b1;
        activation_bits   = 32'hffff_ffff;
        #1;
        if ((selected_even_sum !== 9'd0) ||
            (selected_odd_sum !== 9'd0)) begin
            $display("FAIL: SRAM pair enable caused CIM E/O=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 9 - sram_pair_en alone cannot start CIM");
        end
        sram_pair_en = 16'b0;

        // Test 10: fill all 32 rows of pair 7 with weight 15.  Each selected
        // 32x4 segment must reach the lecture maximum 32*15=480.
        $display("\nTest 10 - maximum bank sum on middle pair 7");
        for (row_index = 0; row_index < 32; row_index = row_index + 1)
            write_pair_row(7, row_index, 4'hf, 4'hf);

        cim_group_en    = 1'b1;
        cim_pair_en     = 16'b0;
        cim_pair_en[7]  = 1'b1;
        activation_bits = 32'hffff_ffff;
        #1;

        if ((selected_even_sum !== 9'd480) ||
            (selected_odd_sum !== 9'd480)) begin
            $display("FAIL: maximum pair expected 480/480, actual=%0d/%0d",
                     selected_even_sum, selected_odd_sum);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 10 - even and odd segments each reach 480");
        end

        cim_group_en    = 1'b0;
        cim_pair_en     = 16'b0;
        activation_bits = 32'b0;

        $display("====================================================================");
        if (error_count == 0) begin
            $display("PASS: all dcim_row_group tests passed");
        end else begin
            $display("FAIL: %0d dcim_row_group checks failed", error_count);
            $fatal(1);
        end
        $display("====================================================================");

        $finish;
    end

endmodule
