`timescale 1ns/1ps

module tb_dcim_macro_core;

    logic        clk = 1'b0;
    logic        model_rst_n;
    logic        reset1;
    logic        reset2;
    logic [6:0]  row_addr;
    logic [3:0]  bank_addr;
    logic        mode_sel;
    logic        wl_en;
    logic        write_en;
    logic        sense_en;
    logic        pre_en;
    logic        clk_en;
    logic        sel_next;
    logic [3:0]  din;
    logic        output_en;
    logic        nv_store;
    logic        nv_recall;
    logic        pd_en;

    logic [3:0]  selected_even_read_data;
    logic [3:0]  selected_odd_read_data;
    logic        selected_pair_read_valid;
    logic [8:0]  selected_even_partial_sum;
    logic [8:0]  selected_odd_partial_sum;
    logic [17:0] even_accumulated_sum;
    logic [17:0] odd_accumulated_sum;
    logic        sume;
    logic        sumo;
    logic        serial_read_bit;

    integer error_count;
    integer bit_index;
    integer stage_index;
    integer expected_even_acc;
    integer expected_odd_acc;
    integer expected_even_partial;
    integer expected_odd_partial;

    logic [7:0]  activation_row0;
    logic [7:0]  activation_row1;
    logic [31:0] activation_plane;
    logic [17:0] captured_even_serial;
    logic [17:0] captured_odd_serial;
    logic [7:0]  captured_sram_read;
    integer      read_bit_index;

    always #5 clk = ~clk;

    dcim_macro_core dut (
        .clk                       (clk),
        .model_rst_n               (model_rst_n),
        .reset1                    (reset1),
        .reset2                    (reset2),
        .row_addr                  (row_addr),
        .bank_addr                 (bank_addr),
        .mode_sel                  (mode_sel),
        .wl_en                     (wl_en),
        .write_en                  (write_en),
        .sense_en                  (sense_en),
        .pre_en                    (pre_en),
        .clk_en                    (clk_en),
        .sel_next                  (sel_next),
        .din                       (din),
        .output_en                 (output_en),
        .nv_store                  (nv_store),
        .nv_recall                 (nv_recall),
        .pd_en                     (pd_en),
        .selected_even_read_data   (selected_even_read_data),
        .selected_odd_read_data    (selected_odd_read_data),
        .selected_pair_read_valid  (selected_pair_read_valid),
        .selected_even_partial_sum (selected_even_partial_sum),
        .selected_odd_partial_sum  (selected_odd_partial_sum),
        .even_accumulated_sum      (even_accumulated_sum),
        .odd_accumulated_sum       (odd_accumulated_sum),
        .sume                      (sume),
        .sumo                      (sumo)
    );

    // Independent Macro-level integration check for the SRAM serializer.
    // The completed dcim_chip_pin_top owns the production instance; this
    // testbench copy keeps Macro read timing directly observable and verified.
    sram_read_serializer_8bit read_serializer (
        .clk             (clk),
        .rst_n           (model_rst_n),
        .even_read_data  (selected_even_read_data),
        .odd_read_data   (selected_odd_read_data),
        .pair_read_valid (selected_pair_read_valid),
        .serial_read_bit (serial_read_bit)
    );

    // The lecture loads the high nibble first and the low nibble second.
    // After two clocks, stage1 is the high nibble and stage0 is the low
    // nibble.  The approved macro mapping sends high->even and low->odd.
    task automatic load_sram_write_word(input logic [7:0] write_word);
        begin
            @(negedge clk);
            mode_sel = 1'b0;
            sel_next = 1'b0;
            clk_en   = 1'b1;
            din      = write_word[7:4];
            @(posedge clk);
            #1;

            @(negedge clk);
            din = write_word[3:0];
            @(posedge clk);
            #1;

            @(negedge clk);
            clk_en   = 1'b0;
            sel_next = 1'b1;
            din      = 4'b0000;
        end
    endtask

    task automatic write_weight(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] write_word
    );
        begin
            load_sram_write_word(write_word);

            row_addr = address;
            bank_addr = pair_address;
            wl_en = 1'b1;
            write_en = 1'b1;
            sense_en = 1'b0;
            @(posedge clk);
            #1;

            $display("  write A=%3d B=%2d word=0x%02h -> even=%0h odd=%0h",
                     address, pair_address, write_word,
                     write_word[7:4], write_word[3:0]);

            @(negedge clk);
            write_en = 1'b0;
            wl_en = 1'b0;
        end
    endtask

    task automatic check_weight_read(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [3:0] expected_even,
        input logic [3:0] expected_odd
    );
        begin
            captured_sram_read = 8'b0;

            @(negedge clk);
            mode_sel = 1'b0;
            row_addr = address;
            bank_addr = pair_address;
            wl_en = 1'b1;
            write_en = 1'b0;
            sense_en = 1'b1;
            pre_en = 1'b1;

            // Bank/Array readback is now combinational.  It must be stable
            // before the first clock so the serializer can be the only
            // read-output register.
            #1;
            if ((selected_pair_read_valid !== 1'b1) ||
                (selected_even_read_data !== expected_even) ||
                (selected_odd_read_data !== expected_odd)) begin
                $display("FAIL: combinational read A=%0d B=%0d expected E/O=%0h/%0h actual=%0h/%0h pair_valid=%b",
                         address, pair_address, expected_even, expected_odd,
                         selected_even_read_data, selected_odd_read_data,
                         selected_pair_read_valid);
                error_count = error_count + 1;
            end

            // This is the first rising edge after sense_en.  The serializer
            // captures {even,odd}, and bit[7] must be visible immediately.
            @(posedge clk);
            #1;
            captured_sram_read[7] = serial_read_bit;
            if (serial_read_bit !== expected_even[3]) begin
                $display("FAIL: first sense edge did not expose bit[7], expected=%0b actual=%0b",
                         expected_even[3], serial_read_bit);
                error_count = error_count + 1;
            end else begin
                $display("  first sense edge -> serial bit[7]=%0b : PASS",
                         serial_read_bit);
            end

            // Deassert sense before the next rising edge so the serializer
            // shifts instead of reloading the same byte.
            @(negedge clk);
            sense_en = 1'b0;
            pre_en = 1'b0;
            wl_en = 1'b0;

            #1;
            if ((selected_pair_read_valid !== 1'b0) ||
                (selected_even_read_data !== 4'b0) ||
                (selected_odd_read_data !== 4'b0)) begin
                $display("FAIL: combinational read path did not turn off with sense_en");
                error_count = error_count + 1;
            end

            for (read_bit_index = 6; read_bit_index >= 0;
                 read_bit_index = read_bit_index - 1) begin
                @(posedge clk);
                #1;
                captured_sram_read[read_bit_index] = serial_read_bit;
            end

            if (captured_sram_read !== {expected_even, expected_odd}) begin
                $display("FAIL: SRAM serial read reconstructed=%02h expected=%02h",
                         captured_sram_read, {expected_even, expected_odd});
                error_count = error_count + 1;
            end else begin
                $display("  read A=%3d B=%2d -> serial byte=0x%02h : PASS",
                         address, pair_address, captured_sram_read);
            end

            @(posedge clk);
            #1;
            if (serial_read_bit !== 1'b0) begin
                $display("FAIL: SRAM serial output did not return to zero");
                error_count = error_count + 1;
            end
        end
    endtask

    // Input Buffer stage0 represents rows 0..3 and stage7 rows 28..31.
    // Because it is a shift chain, stage7 data must be sent first and stage0
    // data last to obtain the requested 32-bit row vector.
    task automatic load_activation_plane(input logic [31:0] plane_bits);
        begin
            mode_sel = 1'b1;
            sel_next = 1'b0;
            clk_en = 1'b1;

            for (stage_index = 7; stage_index >= 0;
                 stage_index = stage_index - 1) begin
                @(negedge clk);
                din = plane_bits[(stage_index * 4) +: 4];
                @(posedge clk);
                #1;
            end

            @(negedge clk);
            clk_en = 1'b0;
            sel_next = 1'b1;
            din = 4'b0000;
        end
    endtask

    task automatic execute_bit_plane(
        input logic [31:0] plane_bits,
        input integer expected_partial_even,
        input integer expected_partial_odd,
        input integer expected_acc_even,
        input integer expected_acc_odd
    );
        begin
            load_activation_plane(plane_bits);

            row_addr = 7'd0;   // A[6:5]=00 selects global rows 0..31.
            bank_addr = 4'd0;
            mode_sel = 1'b1;
            wl_en = 1'b0;
            write_en = 1'b0;
            sense_en = 1'b0;
            #1;

            if ((selected_even_partial_sum !== expected_partial_even[8:0]) ||
                (selected_odd_partial_sum !== expected_partial_odd[8:0])) begin
                $display("FAIL: bit %0d partial expected E/O=%0d/%0d actual=%0d/%0d",
                         bit_index, expected_partial_even, expected_partial_odd,
                         selected_even_partial_sum, selected_odd_partial_sum);
                error_count = error_count + 1;
            end

            output_en = 1'b1;
            @(posedge clk);
            #1;
            output_en = 1'b0;

            $display("  activation bit %0d: partial E/O=%2d/%2d -> ACC E/O=%2d/%2d",
                     bit_index, selected_even_partial_sum,
                     selected_odd_partial_sum,
                     even_accumulated_sum, odd_accumulated_sum);

            if ((even_accumulated_sum !== expected_acc_even[17:0]) ||
                (odd_accumulated_sum !== expected_acc_odd[17:0])) begin
                $display("FAIL: bit %0d accumulator expected E/O=%0d/%0d",
                         bit_index, expected_acc_even, expected_acc_odd);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        model_rst_n = 1'b0;
        reset1 = 1'b1;
        reset2 = 1'b1;
        row_addr = 7'd0;
        bank_addr = 4'd0;
        mode_sel = 1'b0;
        wl_en = 1'b0;
        write_en = 1'b0;
        sense_en = 1'b0;
        pre_en = 1'b0;
        clk_en = 1'b0;
        sel_next = 1'b0;
        din = 4'b0000;
        output_en = 1'b0;
        nv_store = 1'b0;
        nv_recall = 1'b0;
        pd_en = 1'b0;
        error_count = 0;
        activation_row0 = 8'd3;
        activation_row1 = 8'd2;
        activation_plane = 32'b0;
        captured_even_serial = 18'b0;
        captured_odd_serial = 18'b0;
        captured_sram_read = 8'b0;

        $display("================================================================================");
        $display("Testbench : tb_dcim_macro_core");
        $display("Reference : Proposal Figure 4 and 0622.pptx slides 2-6, 12, 14-15");
        $display("Flow      : SRAM write/read -> 8 UINT8 bit planes -> dual 18-bit serial");
        $display("Mapping   : first/high nibble -> even, second/low nibble -> odd");
        $display("================================================================================");

        repeat (2) @(posedge clk);
        #1;
        if ((selected_pair_read_valid !== 1'b0) ||
            (selected_even_partial_sum !== 9'd0) ||
            (selected_odd_partial_sum !== 9'd0) ||
            (even_accumulated_sum !== 18'd0) ||
            (odd_accumulated_sum !== 18'd0) ||
            (sume !== 1'b0) || (sumo !== 1'b0) ||
            (serial_read_bit !== 1'b0)) begin
            $display("FAIL: Test 1 - reset state is not all zero");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - model/reset1/reset2 domains start at zero");
        end

        @(negedge clk);
        model_rst_n = 1'b1;
        reset1 = 1'b0;
        reset2 = 1'b0;

        $display("\nTest 2 - write two group-0 weights and one boundary weight");
        write_weight(7'd0,  4'd0,  8'ha5);
        write_weight(7'd1,  4'd0,  8'h32);
        write_weight(7'd32, 4'd15, 8'hc9);

        $display("\nTest 3 - parallel SRAM readback and address isolation");
        check_weight_read(7'd0,  4'd0,  4'ha, 4'h5);
        check_weight_read(7'd1,  4'd0,  4'h3, 4'h2);
        check_weight_read(7'd32, 4'd15, 4'hc, 4'h9);

        // Clearing only the accumulator must never clear the weight cells.
        $display("\nTest 4 - accumulator reset is isolated from stored weights");
        reset1 = 1'b1;
        #1;
        reset1 = 1'b0;
        check_weight_read(7'd0, 4'd0, 4'ha, 4'h5);
        $display("PASS: Test 4 - active-high reset1 does not erase the SRAM array");

        // Dot products:
        // even = 3*10 + 2*3 = 36
        // odd  = 3*5  + 2*2 = 19
        $display("\nTest 5 - eight MSB-first UINT8 activation bit planes");
        expected_even_acc = 0;
        expected_odd_acc = 0;

        for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
            activation_plane = 32'b0;
            activation_plane[0] = activation_row0[bit_index];
            activation_plane[1] = activation_row1[bit_index];

            expected_even_partial =
                (activation_row0[bit_index] ? 10 : 0) +
                (activation_row1[bit_index] ?  3 : 0);
            expected_odd_partial =
                (activation_row0[bit_index] ? 5 : 0) +
                (activation_row1[bit_index] ? 2 : 0);

            expected_even_acc = (expected_even_acc << 1) +
                                expected_even_partial;
            expected_odd_acc = (expected_odd_acc << 1) +
                               expected_odd_partial;

            execute_bit_plane(activation_plane,
                              expected_even_partial,
                              expected_odd_partial,
                              expected_even_acc,
                              expected_odd_acc);
        end

        if ((even_accumulated_sum !== 18'd36) ||
            (odd_accumulated_sum !== 18'd19)) begin
            $display("FAIL: Test 5 - final dot products expected E/O=36/19");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 5 - final dot products are even=36 and odd=19");
        end

        // The eighth execute_bit_plane call has already loaded each result
        // into its local serial stage.  Therefore sume/sumo currently expose
        // bit[17]; no external serial_load pulse is needed.
        $display("\nTest 6 - reconstruct both automatic 18-bit serial outputs");
        for (bit_index = 17; bit_index >= 0; bit_index = bit_index - 1) begin
            captured_even_serial[bit_index] = sume;
            captured_odd_serial[bit_index] = sumo;
            $display("  serial bit %2d: sume=%0b sumo=%0b",
                     bit_index, sume, sumo);
            @(posedge clk);
            #1;
        end

        if ((captured_even_serial !== 18'd36) ||
            (captured_odd_serial !== 18'd19)) begin
            $display("FAIL: Test 6 - reconstructed E/O=%0d/%0d expected 36/19",
                     captured_even_serial, captured_odd_serial);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 6 - sume/sumo reconstruct even=36 and odd=19");
        end

        $display("================================================================================");
        if (error_count == 0) begin
            $display("PASS: complete dcim_macro_core integration flow passed");
        end else begin
            $display("FAIL: %0d macro-core checks failed", error_count);
            $fatal(1);
        end
        $display("================================================================================");

        $finish;
    end

endmodule
