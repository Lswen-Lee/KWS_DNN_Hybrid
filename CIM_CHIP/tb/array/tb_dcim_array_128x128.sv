`timescale 1ns/1ps

module tb_dcim_array_128x128;

    logic         clk = 1'b0;
    logic         rst_n;
    logic [127:0] wl_select;
    logic         write_en;
    logic         sense_en;
    logic [15:0]  sram_pair_en;
    logic [15:0]  cim_pair_en;
    logic [3:0]   even_write_data;
    logic [3:0]   odd_write_data;
    logic [3:0]   cim_group_select;
    logic [31:0]  activation_group_bits [0:3];
    logic         nv_store;
    logic         nv_recall;
    logic         pd_en;
    logic [3:0]   selected_even_read_data;
    logic [3:0]   selected_odd_read_data;
    logic         selected_pair_read_valid;
    logic [8:0]   selected_even_sum;
    logic [8:0]   selected_odd_sum;

    integer error_count;
    integer row_index;
    integer group_index;

    always #5 clk = ~clk;

    dcim_array_128x128 dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .wl_select                 (wl_select),
        .write_en                  (write_en),
        .sense_en                  (sense_en),
        .sram_pair_en              (sram_pair_en),
        .cim_pair_en               (cim_pair_en),
        .even_write_data           (even_write_data),
        .odd_write_data            (odd_write_data),
        .cim_group_select          (cim_group_select),
        .activation_group_bits     (activation_group_bits),
        .nv_store                  (nv_store),
        .nv_recall                 (nv_recall),
        .pd_en                     (pd_en),
        .selected_even_read_data   (selected_even_read_data),
        .selected_odd_read_data    (selected_odd_read_data),
        .selected_pair_read_valid  (selected_pair_read_valid),
        .selected_even_sum         (selected_even_sum),
        .selected_odd_sum          (selected_odd_sum)
    );

    task automatic clear_activation_inputs;
        begin
            activation_group_bits[0] = 32'b0;
            activation_group_bits[1] = 32'b0;
            activation_group_bits[2] = 32'b0;
            activation_group_bits[3] = 32'b0;
        end
    endtask

    task automatic write_global_row(
        input integer global_row,
        input integer pair_number,
        input logic [3:0] even_value,
        input logic [3:0] odd_value
    );
        begin
            @(negedge clk);
            wl_select                 = 128'b0;
            wl_select[global_row]     = 1'b1;
            sram_pair_en              = 16'b0;
            sram_pair_en[pair_number] = 1'b1;
            cim_pair_en               = 16'b0;
            even_write_data           = even_value;
            odd_write_data            = odd_value;
            write_en                  = 1'b1;
            sense_en                  = 1'b0;

            @(posedge clk);
            #1;
            $display("  write global row %3d (group %0d/local %2d), pair %2d -> even=%0h odd=%0h",
                     global_row, global_row / 32, global_row % 32,
                     pair_number, even_value, odd_value);

            @(negedge clk);
            write_en     = 1'b0;
            wl_select    = 128'b0;
            sram_pair_en = 16'b0;
        end
    endtask

    task automatic check_global_read(
        input integer global_row,
        input integer pair_number,
        input logic [3:0] expected_even,
        input logic [3:0] expected_odd
    );
        begin
            @(negedge clk);
            wl_select                 = 128'b0;
            wl_select[global_row]     = 1'b1;
            sram_pair_en              = 16'b0;
            sram_pair_en[pair_number] = 1'b1;
            write_en                  = 1'b0;
            sense_en                  = 1'b1;

            @(posedge clk);
            #1;
            if ((selected_pair_read_valid !== 1'b1) ||
                (selected_even_read_data !== expected_even) ||
                (selected_odd_read_data !== expected_odd)) begin
                $display("FAIL: read row %0d pair %0d expected E/O=%0h/%0h, actual=%0h/%0h, pair_valid=%b",
                         global_row, pair_number, expected_even, expected_odd,
                         selected_even_read_data, selected_odd_read_data,
                         selected_pair_read_valid);
                error_count = error_count + 1;
            end else begin
                $display("  read  global row %3d (group %0d/local %2d), pair %2d <- even=%0h odd=%0h : PASS",
                         global_row, global_row / 32, global_row % 32,
                         pair_number, selected_even_read_data,
                         selected_odd_read_data);
            end

            @(negedge clk);
            sense_en     = 1'b0;
            wl_select    = 128'b0;
            sram_pair_en = 16'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic check_cim_result(
        input integer group_number,
        input integer pair_number,
        input logic [31:0] activation_value,
        input logic [8:0] expected_even,
        input logic [8:0] expected_odd,
        input [255:0] description
    );
        begin
            cim_group_select               = 4'b0000;
            cim_group_select[group_number] = 1'b1;
            cim_pair_en                    = 16'b0;
            cim_pair_en[pair_number]       = 1'b1;
            sram_pair_en                   = 16'b0;
            clear_activation_inputs();
            activation_group_bits[group_number] = activation_value;
            #1;

            if ((selected_even_sum !== expected_even) ||
                (selected_odd_sum !== expected_odd)) begin
                $display("FAIL: %0s group=%0d pair=%0d expected E/O=%0d/%0d, actual=%0d/%0d",
                         description, group_number, pair_number,
                         expected_even, expected_odd,
                         selected_even_sum, selected_odd_sum);
                error_count = error_count + 1;
            end else begin
                $display("  %0s group=%0d pair=%0d -> even=%0d odd=%0d : PASS",
                         description, group_number, pair_number,
                         selected_even_sum, selected_odd_sum);
            end
        end
    endtask

    initial begin
        rst_n                    = 1'b0;
        wl_select                = 128'b0;
        write_en                 = 1'b0;
        sense_en                 = 1'b0;
        sram_pair_en             = 16'b0;
        cim_pair_en              = 16'b0;
        even_write_data          = 4'b0;
        odd_write_data           = 4'b0;
        cim_group_select         = 4'b0;
        nv_store                 = 1'b0;
        nv_recall                = 1'b0;
        pd_en                    = 1'b0;
        error_count              = 0;
        clear_activation_inputs();

        $display("====================================================================");
        $display("Testbench : tb_dcim_array_128x128");
        $display("Reference : 0622.pptx slides 2 and 6; Proposal Figure 4");
        $display("Structure : 4 groups x 32 rows x 128 columns = 16384 cells");
        $display("CIM output: select pair/group products, then two shared adder trees");
        $display("====================================================================");

        repeat (2) @(posedge clk);
        #1;
        if ((selected_even_read_data !== 4'b0) ||
            (selected_odd_read_data !== 4'b0) ||
            (selected_pair_read_valid !== 1'b0) ||
            (selected_even_sum !== 9'b0) ||
            (selected_odd_sum !== 9'b0)) begin
            $display("FAIL: Test 1 - reset/disabled outputs are not zero");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - reset and disabled controls produce zero outputs");
        end
        rst_n = 1'b1;

        // Store different values at local row 0 in all four row groups.  This
        // verifies global-row slicing and group isolation with the same pair.
        $display("\nTest 2 - four row-group boundaries and SRAM isolation");
        write_global_row(0,  0, 4'h1, 4'h2);
        write_global_row(32, 0, 4'h3, 4'h4);
        write_global_row(64, 0, 4'h5, 4'h6);
        write_global_row(96, 0, 4'h7, 4'h8);
        check_global_read(0,  0, 4'h1, 4'h2);
        check_global_read(32, 0, 4'h3, 4'h4);
        check_global_read(64, 0, 4'h5, 4'h6);
        check_global_read(96, 0, 4'h7, 4'h8);

        // Last global row and final pair prove both array dimensions reach
        // their upper boundaries without wrapping.
        $display("\nTest 3 - final row 127 and final pair 15");
        write_global_row(127, 15, 4'ha, 4'hd);
        check_global_read(127, 15, 4'ha, 4'hd);
        check_global_read(0, 0, 4'h1, 4'h2);

        // Each group has a different value at local row 0.  Selecting groups
        // one by one verifies group-to-bank merging and the two OR trees.
        $display("\nTest 4 - CIM selection across all four row groups");
        check_cim_result(0, 0, 32'h0000_0001, 9'd1, 9'd2,
                         "group 0 value");
        check_cim_result(1, 0, 32'h0000_0001, 9'd3, 9'd4,
                         "group 1 value");
        check_cim_result(2, 0, 32'h0000_0001, 9'd5, 9'd6,
                         "group 2 value");
        check_cim_result(3, 0, 32'h0000_0001, 9'd7, 9'd8,
                         "group 3 value");

        // The activation fanout belonging to an unselected group must not be
        // consumed by the selected group.
        $display("\nTest 5 - activation group wiring and group enable gating");
        cim_group_select = 4'b0001;
        cim_pair_en      = 16'b0000_0000_0000_0001;
        clear_activation_inputs();
        activation_group_bits[1] = 32'h0000_0001;
        #1;
        if ((selected_even_sum !== 9'b0) ||
            (selected_odd_sum !== 9'b0)) begin
            $display("FAIL: unselected group activation reached group 0");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5a - each row group uses only its own 32-bit fanout");
        end

        cim_group_select = 4'b0000;
        clear_activation_inputs();
        activation_group_bits[0] = 32'hffff_ffff;
        #1;
        if ((selected_even_sum !== 9'b0) ||
            (selected_odd_sum !== 9'b0)) begin
            $display("FAIL: disabled CIM groups produced a nonzero result");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5b - no group selected forces both CIM sums to zero");
        end

        // Pair 15 and local row 31 correspond to global row 127.  The output
        // must pass through the last even/odd OR-tree input slots.
        $display("\nTest 6 - last group, last local row and last pair CIM path");
        check_cim_result(3, 15, 32'h8000_0000, 9'd10, 9'd13,
                         "upper array boundary");

        // Fill one complete 32x4 pair in group 2.  The expected value is the
        // maximum shown in the presentation: 32 rows x weight 15 = 480.
        $display("\nTest 7 - maximum 32-row partial sum through the full array");
        cim_group_select = 4'b0;
        cim_pair_en      = 16'b0;
        clear_activation_inputs();
        for (row_index = 64; row_index < 96; row_index = row_index + 1)
            write_global_row(row_index, 7, 4'hf, 4'hf);

        check_cim_result(2, 7, 32'hffff_ffff, 9'd480, 9'd480,
                         "maximum partial sum");

        // SRAM control alone must never activate the CIM NAND/NOR path.
        $display("\nTest 8 - SRAM and CIM pair controls remain independent");
        cim_group_select   = 4'b0100;
        cim_pair_en        = 16'b0;
        sram_pair_en       = 16'b0000_0000_1000_0000;
        clear_activation_inputs();
        activation_group_bits[2] = 32'hffff_ffff;
        #1;
        if ((selected_even_sum !== 9'b0) ||
            (selected_odd_sum !== 9'b0)) begin
            $display("FAIL: SRAM pair enable incorrectly started CIM computation");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 8 - SRAM pair enable cannot start CIM");
        end

        cim_group_select = 4'b0;
        cim_pair_en      = 16'b0;
        sram_pair_en     = 16'b0;
        clear_activation_inputs();

        $display("====================================================================");
        if (error_count == 0) begin
            $display("PASS: all dcim_array_128x128 tests passed");
        end else begin
            $display("FAIL: %0d dcim_array_128x128 checks failed", error_count);
            $fatal(1);
        end
        $display("====================================================================");

        $finish;
    end

endmodule
