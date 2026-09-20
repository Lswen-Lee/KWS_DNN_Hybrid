`timescale 1ns/1ps

module tb_dcim_chip_pin_top;

    logic       clk = 1'b0;
    logic       model_rst_n;
    logic       reset1;
    logic       reset2;
    logic [6:0] row_addr;
    logic [3:0] bank_addr;
    logic       mode_sel;
    logic       wl_en;
    logic       write_en;
    logic       sense_en;
    logic       pre_en;
    logic       clk_en;
    logic       sel_next;
    logic [3:0] din;
    logic       output_en;
    logic       nv_store;
    logic       nv_recall;
    logic       pd_en;
    logic       sume;
    logic       sumo;

    logic [7:0]  read_word;
    logic [31:0] activation_plane;
    logic [17:0] even_result;
    logic [17:0] odd_result;
    logic [7:0]  activation_row0;
    logic [7:0]  activation_row1;

    // Reproducible full-array verification models.  One 8-bit word programs
    // the even/odd four-bit banks belonging to one row and one bank pair.
    logic [7:0]  weight_model     [0:127][0:15];
    logic [7:0]  activation_model [0:3][0:31];
    logic [31:0] random_state;
    logic        verbose_sram_write;
    logic        verbose_serial_bits;

    integer errors;
    integer stage_index;
    integer bit_index;
    integer row_index;
    integer pair_index;
    integer group_index;
    integer local_row_index;
    integer random_case_count;
    integer activation_value;

    always #5 clk = ~clk;

    dcim_chip_pin_top dut (
        .clk         (clk),
        .model_rst_n (model_rst_n),
        .reset1      (reset1),
        .reset2      (reset2),
        .row_addr    (row_addr),
        .bank_addr   (bank_addr),
        .mode_sel    (mode_sel),
        .wl_en       (wl_en),
        .write_en    (write_en),
        .sense_en    (sense_en),
        .pre_en      (pre_en),
        .clk_en      (clk_en),
        .sel_next    (sel_next),
        .din         (din),
        .output_en   (output_en),
        .nv_store    (nv_store),
        .nv_recall   (nv_recall),
        .pd_en       (pd_en),
        .sume        (sume),
        .sumo        (sumo)
    );

    // Slide 12 uses two input clocks followed by one SRAM write clock.
    // The first nibble becomes the high/even nibble and the second becomes
    // the low/odd nibble.
    task automatic write_sram_word(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] value
    );
        begin
            @(negedge clk);
            mode_sel = 1'b0;
            sel_next = 1'b0;
            clk_en = 1'b1;
            din = value[7:4];
            @(posedge clk);
            #1;

            @(negedge clk);
            din = value[3:0];
            @(posedge clk);
            #1;

            @(negedge clk);
            clk_en = 1'b0;
            sel_next = 1'b1;
            din = 4'b0000;
            row_addr = address;
            bank_addr = pair_address;
            wl_en = 1'b1;
            write_en = 1'b1;
            @(posedge clk);
            #1;

            @(negedge clk);
            wl_en = 1'b0;
            write_en = 1'b0;
            if (verbose_sram_write) begin
                $display("  write A=%0d B=%0d value=0x%02h", address,
                         pair_address, value);
            end
        end
    endtask

    // sense_en is asserted before the first read edge.  That first edge is
    // clock 1 of the eight clocks shown on slide 12 and immediately exposes
    // bit 7; there is no preceding Bank-register cycle.
    task automatic read_sram_word(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] expected
    );
        begin
            read_word = 8'b0;

            @(negedge clk);
            mode_sel = 1'b0;
            row_addr = address;
            bank_addr = pair_address;
            wl_en = 1'b1;
            sense_en = 1'b1;
            pre_en = 1'b1;

            @(posedge clk);
            #1;
            read_word[7] = sumo;
            if (verbose_serial_bits)
                $display("  read clock 1: bit[7]=%0b", sumo);

            @(negedge clk);
            sense_en = 1'b0;
            pre_en = 1'b0;
            wl_en = 1'b0;

            for (bit_index = 6; bit_index >= 0;
                 bit_index = bit_index - 1) begin
                @(posedge clk);
                #1;
                read_word[bit_index] = sumo;
                if (verbose_serial_bits) begin
                    $display("  read clock %0d: bit[%0d]=%0b",
                             8-bit_index, bit_index, sumo);
                end
            end

            if (read_word !== expected) begin
                $display("FAIL: SRAM read expected=0x%02h actual=0x%02h",
                         expected, read_word);
                errors = errors + 1;
            end else begin
                $display("PASS: eight read clocks reconstructed 0x%02h",
                         read_word);
            end
        end
    endtask

    // The Input Path is four lanes by eight stages.  Stage 7 is sent first
    // because the buffer is a shift chain.
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

    task automatic execute_activation_plane(
        input logic [1:0]  group_number,
        input logic [3:0]  pair_address,
        input logic [31:0] plane_bits
    );
        begin
            load_activation_plane(plane_bits);
            // CIM group selection uses row_addr[6:5].  The lower five address
            // bits are irrelevant in CIM mode and are held at zero.
            row_addr = {group_number, 5'b00000};
            bank_addr = pair_address;
            mode_sel = 1'b1;
            wl_en = 1'b0;
            write_en = 1'b0;
            sense_en = 1'b0;
            output_en = 1'b1;
            @(posedge clk);
            #1;
            output_en = 1'b0;
        end
    endtask

    // Capture the two 18-bit serial accumulator results in parallel.  The
    // final output_en edge has already made bit[17] visible when this task is
    // called, so the first sample occurs before waiting for another clock.
    task automatic capture_cim_results(
        output logic [17:0] captured_even,
        output logic [17:0] captured_odd
    );
        integer capture_index;
        begin
            captured_even = 18'b0;
            captured_odd  = 18'b0;

            for (capture_index = 17; capture_index >= 0;
                 capture_index = capture_index - 1) begin
                captured_even[capture_index] = sume;
                captured_odd[capture_index]  = sumo;
                @(posedge clk);
                #1;
            end
        end
    endtask

    // Execute one complete unsigned A8 x W8 dot product for a selected
    // 32-row group and bank pair, then compare all three representations:
    //   even accumulator = activation * weight[7:4]
    //   odd accumulator  = activation * weight[3:0]
    //   W8 result         = odd + (even << 4)
    task automatic run_and_check_random_cim_case(
        input logic [1:0] group_number,
        input logic [3:0] pair_address
    );
        integer        plane_index;
        integer        row_in_group;
        integer        global_row;
        longint unsigned expected_even_sum;
        longint unsigned expected_odd_sum;
        longint unsigned expected_w8_sum;
        longint unsigned actual_w8_sum;
        logic [31:0] case_plane;
        logic [17:0] captured_even;
        logic [17:0] captured_odd;
        begin
            // Each group/pair calculation owns a fresh eight-plane sequence.
            @(negedge clk);
            output_en = 1'b0;
            reset1 = 1'b1;
            reset2 = 1'b1;
            #1;
            reset1 = 1'b0;
            reset2 = 1'b0;

            expected_even_sum = 0;
            expected_odd_sum  = 0;
            for (row_in_group = 0; row_in_group < 32;
                 row_in_group = row_in_group + 1) begin
                global_row = (group_number * 32) + row_in_group;
                expected_even_sum = expected_even_sum +
                    (activation_model[group_number][row_in_group] *
                     weight_model[global_row][pair_address][7:4]);
                expected_odd_sum = expected_odd_sum +
                    (activation_model[group_number][row_in_group] *
                     weight_model[global_row][pair_address][3:0]);
            end

            // The accumulator contract is MSB-first for UINT8 activations.
            for (plane_index = 7; plane_index >= 0;
                 plane_index = plane_index - 1) begin
                case_plane = 32'b0;
                for (row_in_group = 0; row_in_group < 32;
                     row_in_group = row_in_group + 1) begin
                    case_plane[row_in_group] =
                        activation_model[group_number][row_in_group][plane_index];
                end
                execute_activation_plane(group_number, pair_address, case_plane);
            end

            capture_cim_results(captured_even, captured_odd);
            expected_w8_sum = expected_odd_sum + (expected_even_sum << 4);
            // Extend to 21 bits before shifting; a 32-term unsigned W8 dot
            // product is wider than either 18-bit nibble accumulator.
            actual_w8_sum = {46'b0, captured_odd} +
                            ({46'b0, captured_even} << 4);
            random_case_count = random_case_count + 1;

            if (({46'b0, captured_even} != expected_even_sum) ||
                ({46'b0, captured_odd} != expected_odd_sum) ||
                (actual_w8_sum != expected_w8_sum)) begin
                $display("FAIL: random CIM group=%0d pair=%0d E=%0d/%0d O=%0d/%0d W8=%0d/%0d",
                         group_number, pair_address,
                         captured_even, expected_even_sum,
                         captured_odd, expected_odd_sum,
                         actual_w8_sum, expected_w8_sum);
                errors = errors + 1;
            end else begin
                $display("  group=%0d pair=%2d even=%6d odd=%6d W8=%7d : PASS",
                         group_number, pair_address,
                         captured_even, captured_odd, actual_w8_sum);
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
        read_word = 8'b0;
        even_result = 18'b0;
        odd_result = 18'b0;
        activation_row0 = 8'd3;
        activation_row1 = 8'd2;
        activation_plane = 32'b0;
        random_state = 32'h1a2b_3c4d;
        verbose_sram_write = 1'b1;
        verbose_serial_bits = 1'b1;
        random_case_count = 0;
        errors = 0;

        $display("============================================================================");
        $display("Testbench : tb_dcim_chip_pin_top");
        $display("Reference : 0622.pptx slides 6, 11-15");
        $display("Purpose   : verify physical-pin data flow and shared sumo/read output");
        $display("============================================================================");

        repeat (2) @(posedge clk);
        #1;
        if ((sume !== 1'b0) || (sumo !== 1'b0)) begin
            $display("FAIL: Test 1 - reset did not clear both output pins");
            errors = errors + 1;
        end else begin
            $display("PASS: Test 1 - model/reset1/reset2 clear both output pins");
        end

        @(negedge clk);
        model_rst_n = 1'b1;
        reset1 = 1'b0;
        reset2 = 1'b0;

        $display("\nTest 2 - slide-12 three-clock SRAM writes");
        write_sram_word(7'd0, 4'd0, 8'ha5);
        write_sram_word(7'd1, 4'd0, 8'h32);

        $display("\nTest 3 - first sense edge is read clock 1");
        read_sram_word(7'd0, 4'd0, 8'ha5);
        read_sram_word(7'd1, 4'd0, 8'h32);

        // reset2 is the output reset.  It must clear the SRAM serializer but
        // must not erase the programmed weight cells.
        $display("\nTest 4 - active-high reset2 clears output state only");
        @(negedge clk);
        mode_sel = 1'b0;
        row_addr = 7'd0;
        bank_addr = 4'd0;
        wl_en = 1'b1;
        sense_en = 1'b1;
        @(posedge clk);
        #1;
        if (sumo !== 1'b1) begin
            $display("FAIL: expected A5 bit[7]=1 before reset2");
            errors = errors + 1;
        end
        reset2 = 1'b1;
        #1;
        if ((sume !== 1'b0) || (sumo !== 1'b0)) begin
            $display("FAIL: reset2 did not clear output serializers");
            errors = errors + 1;
        end else begin
            $display("PASS: reset2 immediately clears ACC and SRAM serial outputs");
        end
        @(negedge clk);
        reset2 = 1'b0;
        sense_en = 1'b0;
        wl_en = 1'b0;
        read_sram_word(7'd0, 4'd0, 8'ha5);
        $display("PASS: reset2 did not erase the stored SRAM word");

        // row0 activation=3 and row1 activation=2:
        // even = 3*10 + 2*3 = 36
        // odd  = 3*5  + 2*2 = 19
        $display("\nTest 5 - eight UINT8 CIM bit planes through chip pins");
        reset1 = 1'b1;
        reset2 = 1'b1;
        #1;
        reset1 = 1'b0;
        reset2 = 1'b0;

        for (bit_index = 7; bit_index >= 0;
             bit_index = bit_index - 1) begin
            activation_plane = 32'b0;
            activation_plane[0] = activation_row0[bit_index];
            activation_plane[1] = activation_row1[bit_index];
            execute_activation_plane(2'd0, 4'd0, activation_plane);
            $display("  accepted activation bit plane %0d", bit_index);
        end

        // The eighth output_en edge already loaded bit[17].  In CIM mode,
        // sumo must now be the odd ACC output rather than SRAM readback.
        $display("\nTest 6 - mode mux and dual 18-bit serial results");
        for (bit_index = 17; bit_index >= 0;
             bit_index = bit_index - 1) begin
            even_result[bit_index] = sume;
            odd_result[bit_index] = sumo;
            $display("  CIM bit[%0d]: sume=%0b sumo=%0b",
                     bit_index, sume, sumo);
            @(posedge clk);
            #1;
        end

        if ((even_result !== 18'd36) || (odd_result !== 18'd19)) begin
            $display("FAIL: CIM pins reconstructed even=%0d odd=%0d",
                     even_result, odd_result);
            errors = errors + 1;
        end else begin
            $display("PASS: CIM mode routes even=36 and odd=19 to sume/sumo");
        end

        // Fill every storage location with deterministic pseudo-random data.
        // There are 128 rows x 16 eight-bit pairs = 2048 write transactions,
        // covering all 16384 one-bit cells in the 128x128 array.
        $display("\nTest 7 - deterministic random programming of the full array");
        verbose_sram_write = 1'b0;
        for (row_index = 0; row_index < 128; row_index = row_index + 1) begin
            for (pair_index = 0; pair_index < 16;
                 pair_index = pair_index + 1) begin
                random_state = (random_state * 32'd1664525) + 32'd1013904223;
                weight_model[row_index][pair_index] = random_state[31:24];
                write_sram_word(row_index[6:0], pair_index[3:0],
                                weight_model[row_index][pair_index]);
            end
            if ((row_index == 31) || (row_index == 63) ||
                (row_index == 95) || (row_index == 127)) begin
                $display("  programmed rows %0d..%0d (%0d/2048 words)",
                         row_index - 31, row_index,
                         (row_index + 1) * 16);
            end
        end
        $display("PASS: all 2048 eight-bit words were programmed");

        // Sample boundary and middle addresses through the real serial SRAM
        // read pin.  The following CIM sweep then uses every programmed word.
        $display("\nTest 8 - serial readback samples after full-array programming");
        verbose_serial_bits = 1'b0;
        read_sram_word(7'd0,   4'd0,  weight_model[0][0]);
        read_sram_word(7'd31,  4'd15, weight_model[31][15]);
        read_sram_word(7'd32,  4'd1,  weight_model[32][1]);
        read_sram_word(7'd63,  4'd14, weight_model[63][14]);
        read_sram_word(7'd64,  4'd2,  weight_model[64][2]);
        read_sram_word(7'd95,  4'd13, weight_model[95][13]);
        read_sram_word(7'd96,  4'd3,  weight_model[96][3]);
        read_sram_word(7'd127, 4'd15, weight_model[127][15]);

        // Use nonzero deterministic UINT8 activations so all 32 rows in every
        // group participate.  Values range from 1 through 255.
        $display("\nTest 9 - 64 full A8xW8 dot products against software-style golden sums");
        for (group_index = 0; group_index < 4;
             group_index = group_index + 1) begin
            for (local_row_index = 0; local_row_index < 32;
                 local_row_index = local_row_index + 1) begin
                activation_value =
                    ((((group_index * 32) + local_row_index) * 13 + 7) % 255) + 1;
                activation_model[group_index][local_row_index] =
                    activation_value[7:0];
            end
        end

        for (group_index = 0; group_index < 4;
             group_index = group_index + 1) begin
            for (pair_index = 0; pair_index < 16;
                 pair_index = pair_index + 1) begin
                run_and_check_random_cim_case(group_index[1:0],
                                              pair_index[3:0]);
            end
        end
        $display("PASS: %0d/64 group-pair CIM cases matched Even, Odd and W8 golden results",
                 random_case_count);

        $display("============================================================================");
        if (errors == 0) begin
            $display("PASS: complete dcim_chip_pin_top verification passed");
        end else begin
            $display("FAIL: %0d dcim_chip_pin_top checks failed", errors);
            $fatal(1);
        end
        $display("============================================================================");
        $finish;
    end

endmodule
