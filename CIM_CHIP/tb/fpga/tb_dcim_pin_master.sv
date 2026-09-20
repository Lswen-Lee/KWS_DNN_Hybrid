`timescale 1ns/1ps

module tb_dcim_pin_master;

    localparam logic [1:0] OP_WEIGHT_WRITE = 2'd0;
    localparam logic [1:0] OP_SRAM_READ    = 2'd1;
    localparam logic [1:0] OP_CIM_COMPUTE  = 2'd2;
    localparam logic [1:0] OP_WEIGHT_BURST = 2'd3;

    logic         clk = 1'b0;
    logic         rst;
    logic         start;
    logic [1:0]   operation;
    logic [6:0]   command_row_addr;
    logic [3:0]   command_bank_addr;
    logic [7:0]   command_weight;
    logic [255:0] activation_flat;
    logic         activation_is_a8;
    logic [11:0]  command_burst_length;
    logic         burst_weight_valid;
    logic [7:0]   burst_weight_data;
    logic         burst_weight_ready;
    logic [6:0]   burst_weight_row_addr;
    logic [3:0]   burst_weight_bank_addr;
    logic         burst_source_enable;

    logic         busy;
    logic         done;
    logic         result_valid;
    logic         error;
    logic [7:0]   sram_read_data;
    logic [17:0]  even_raw_result;
    logic [17:0]  odd_raw_result;

    logic         chip_model_rst_n;
    logic         chip_reset1;
    logic         chip_reset2;
    logic [6:0]   chip_row_addr;
    logic [3:0]   chip_bank_addr;
    logic         chip_mode_sel;
    logic         chip_wl_en;
    logic         chip_write_en;
    logic         chip_sense_en;
    logic         chip_pre_en;
    logic         chip_clk_en;
    logic         chip_sel_next;
    logic [3:0]   chip_din;
    logic         chip_output_en;
    logic         chip_nv_store;
    logic         chip_nv_recall;
    logic         chip_pd_en;
    logic         chip_sume;
    logic         chip_sumo;

    logic [7:0] weight_model [0:127][0:15];

    integer errors;
    integer row_index;
    integer pair_index;
    integer activation_value;
    integer weight_value;
    integer unsigned expected_even;
    integer unsigned expected_odd;
    integer unsigned expected_w8;
    integer unsigned actual_w8;
    integer cycle_count;
    integer burst_start_cycle;
    integer burst_elapsed_cycles;

    always #10 clk = ~clk;

    always @(posedge clk)
        cycle_count = cycle_count + 1;

    function automatic logic [7:0] burst_test_pattern (
        input logic [6:0] row_value,
        input logic [3:0] bank_value
    );
        begin
            burst_test_pattern = {(row_value[3:0] ^ bank_value),
                                  (row_value[6:3] + bank_value)};
        end
    endfunction

    // The source computes the requested word from the address exported by
    // the master.  Keeping valid high exercises zero-bubble prefetch.
    always_comb begin
        burst_weight_valid = burst_source_enable;
        burst_weight_data  = burst_test_pattern(burst_weight_row_addr,
                                                burst_weight_bank_addr);
    end

    dcim_pin_master dut (
        .clk                    (clk),
        .rst                    (rst),
        .start                  (start),
        .operation              (operation),
        .command_row_addr       (command_row_addr),
        .command_bank_addr      (command_bank_addr),
        .command_weight         (command_weight),
        .activation_flat        (activation_flat),
        .activation_is_a8       (activation_is_a8),
        .command_burst_length   (command_burst_length),
        .burst_weight_valid     (burst_weight_valid),
        .burst_weight_data      (burst_weight_data),
        .burst_weight_ready     (burst_weight_ready),
        .burst_weight_row_addr  (burst_weight_row_addr),
        .burst_weight_bank_addr (burst_weight_bank_addr),
        .busy                   (busy),
        .done                   (done),
        .result_valid           (result_valid),
        .error                  (error),
        .sram_read_data         (sram_read_data),
        .even_raw_result        (even_raw_result),
        .odd_raw_result         (odd_raw_result),
        .chip_model_rst_n       (chip_model_rst_n),
        .chip_reset1            (chip_reset1),
        .chip_reset2            (chip_reset2),
        .chip_row_addr          (chip_row_addr),
        .chip_bank_addr         (chip_bank_addr),
        .chip_mode_sel          (chip_mode_sel),
        .chip_wl_en             (chip_wl_en),
        .chip_write_en          (chip_write_en),
        .chip_sense_en          (chip_sense_en),
        .chip_pre_en            (chip_pre_en),
        .chip_clk_en            (chip_clk_en),
        .chip_sel_next          (chip_sel_next),
        .chip_din               (chip_din),
        .chip_output_en         (chip_output_en),
        .chip_nv_store          (chip_nv_store),
        .chip_nv_recall         (chip_nv_recall),
        .chip_pd_en             (chip_pd_en),
        .chip_sume              (chip_sume),
        .chip_sumo              (chip_sumo)
    );

    dcim_chip_pin_top chip (
        .clk         (clk),
        .model_rst_n (chip_model_rst_n),
        .reset1      (chip_reset1),
        .reset2      (chip_reset2),
        .row_addr    (chip_row_addr),
        .bank_addr   (chip_bank_addr),
        .mode_sel    (chip_mode_sel),
        .wl_en       (chip_wl_en),
        .write_en    (chip_write_en),
        .sense_en    (chip_sense_en),
        .pre_en      (chip_pre_en),
        .clk_en      (chip_clk_en),
        .sel_next    (chip_sel_next),
        .din         (chip_din),
        .output_en   (chip_output_en),
        .nv_store    (chip_nv_store),
        .nv_recall   (chip_nv_recall),
        .pd_en       (chip_pd_en),
        .sume        (chip_sume),
        .sumo        (chip_sumo)
    );

    task automatic wait_for_idle;
        begin
            while (busy || done) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic burst_write_and_check(
        input logic [6:0]  start_row,
        input logic [3:0]  start_bank,
        input logic [11:0] word_count
    );
        integer burst_index;
        integer linear_address;
        integer model_row;
        integer model_bank;
        begin
            command_row_addr     = start_row;
            command_bank_addr    = start_bank;
            command_burst_length = word_count;
            burst_source_enable  = 1'b1;

            wait_for_idle();
            @(negedge clk);
            operation = OP_WEIGHT_BURST;
            start = 1'b1;
            @(posedge clk);
            #1;
            burst_start_cycle = cycle_count;
            start = 1'b0;

            wait_for_done();
            burst_elapsed_cycles = cycle_count - burst_start_cycle;
            burst_source_enable = 1'b0;

            if (error || result_valid) begin
                $display("FAIL: burst returned invalid status error=%0b valid=%0b",
                         error, result_valid);
                errors = errors + 1;
            end

            // With the first stream word valid beside start and no stalls,
            // every word must consume exactly high/low/write = 3 clocks.
            if (burst_elapsed_cycles != (word_count * 3)) begin
                $display("FAIL: burst length=%0d expected cycles=%0d actual=%0d",
                         word_count, word_count * 3, burst_elapsed_cycles);
                errors = errors + 1;
            end else begin
                $display("PASS: %0d-word burst completed in %0d cycles (3 cycles/word)",
                         word_count, burst_elapsed_cycles);
            end

            linear_address = (integer'(start_row) * 16) +
                             integer'(start_bank);
            for (burst_index = 0; burst_index < word_count;
                 burst_index = burst_index + 1) begin
                model_row  = (linear_address + burst_index) / 16;
                model_bank = (linear_address + burst_index) % 16;
                weight_model[model_row][model_bank] =
                    burst_test_pattern(model_row[6:0], model_bank[3:0]);
            end
        end
    endtask

    task automatic start_command(input logic [1:0] requested_operation);
        begin
            wait_for_idle();
            @(negedge clk);
            operation = requested_operation;
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
        end
    endtask

    task automatic wait_for_done;
        begin
            while (!done) begin
                @(posedge clk);
                #1;
            end
        end
    endtask

    task automatic write_weight(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] value
    );
        begin
            command_row_addr  = address;
            command_bank_addr = pair_address;
            command_weight    = value;
            start_command(OP_WEIGHT_WRITE);
            wait_for_done();

            if (error || result_valid) begin
                $display("FAIL: write A=%0d B=%0d produced invalid status", address,
                         pair_address);
                errors = errors + 1;
            end
            weight_model[address][pair_address] = value;
        end
    endtask

    task automatic read_and_check_weight(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] expected
    );
        integer read_start_cycle;
        begin
            command_row_addr  = address;
            command_bank_addr = pair_address;
            start_command(OP_SRAM_READ);
            read_start_cycle = cycle_count;
            while (!done && ((cycle_count - read_start_cycle) < 12)) begin
                if (chip_reset1 || chip_reset2) begin
                    $display("FAIL: SRAM read unexpectedly asserted output reset");
                    errors = errors + 1;
                end
                @(posedge clk);
                #1;
            end
            if (!done || ((cycle_count - read_start_cycle) != 9)) begin
                $display("FAIL: SRAM read expected 9 cycles, actual=%0d done=%0b",
                         cycle_count - read_start_cycle, done);
                errors = errors + 1;
            end

            if (error || !result_valid || (sram_read_data !== expected)) begin
                $display("FAIL: read A=%0d B=%0d expected=0x%02h actual=0x%02h valid=%0b error=%0b",
                         address, pair_address, expected, sram_read_data,
                         result_valid, error);
                errors = errors + 1;
            end else begin
                $display("PASS: SRAM read (9-cycle/no-reset check) A=%0d B=%0d value=0x%02h",
                         address, pair_address, sram_read_data);
            end
        end
    endtask

    task automatic compute_and_check(
        input logic [1:0] group_address,
        input logic [3:0] pair_address,
        input logic       use_a8
    );
        begin
            expected_even = 0;
            expected_odd  = 0;

            for (row_index = 0; row_index < 32; row_index = row_index + 1) begin
                weight_value = {24'd0,
                                weight_model[(group_address * 32) + row_index]
                                            [pair_address]};
                if (use_a8)
                    activation_value =
                        {24'd0, activation_flat[(row_index * 8) +: 8]};
                else
                    activation_value =
                        {28'd0, activation_flat[(row_index * 8) +: 4]};

                expected_even = expected_even +
                                (activation_value * ((weight_value >> 4) & 15));
                expected_odd  = expected_odd +
                                (activation_value * (weight_value & 15));
            end

            command_row_addr  = {group_address, 5'b00000};
            command_bank_addr = pair_address;
            activation_is_a8  = use_a8;
            start_command(OP_CIM_COMPUTE);
            wait_for_done();

            expected_w8 = expected_odd + (expected_even << 4);
            actual_w8   = {14'b0, odd_raw_result} +
                          ({14'b0, even_raw_result} << 4);

            if (error || !result_valid ||
                ({14'b0, even_raw_result} != expected_even) ||
                ({14'b0, odd_raw_result} != expected_odd) ||
                (actual_w8 != expected_w8)) begin
                $display("FAIL: %s group=%0d pair=%0d E=%0d/%0d O=%0d/%0d W8=%0d/%0d",
                         use_a8 ? "A8W8" : "A4W8", group_address, pair_address,
                         even_raw_result, expected_even,
                         odd_raw_result, expected_odd,
                         actual_w8, expected_w8);
                errors = errors + 1;
            end else begin
                $display("PASS: %s group=%0d pair=%0d even=%0d odd=%0d W8=%0d",
                         use_a8 ? "A8W8" : "A4W8", group_address, pair_address,
                         even_raw_result, odd_raw_result, actual_w8);
            end
        end
    endtask

    initial begin
        rst               = 1'b1;
        start             = 1'b0;
        operation         = OP_WEIGHT_WRITE;
        command_row_addr  = 7'd0;
        command_bank_addr = 4'd0;
        command_weight    = 8'd0;
        activation_flat   = 256'd0;
        activation_is_a8  = 1'b0;
        command_burst_length = 12'd0;
        burst_source_enable  = 1'b0;
        errors            = 0;
        cycle_count       = 0;

        for (row_index = 0; row_index < 128; row_index = row_index + 1)
            for (pair_index = 0; pair_index < 16; pair_index = pair_index + 1)
                weight_model[row_index][pair_index] = 8'd0;

        $display("============================================================");
        $display("Testbench : tb_dcim_pin_master");
        $display("Purpose   : verify FPGA transaction FSM against chip pin top");
        $display("============================================================");

        repeat (3) @(posedge clk);
        #1;
        rst = 1'b0;
        @(posedge clk);
        #1;

        if (busy || done || result_valid || error || chip_model_rst_n !== 1'b1) begin
            $display("FAIL: reset/idle outputs are incorrect");
            errors = errors + 1;
        end else begin
            $display("PASS: active-high reset enters a clean idle state");
        end

        // Direct SRAM pin-sequence check at a nontrivial row and pair.
        read_and_check_weight(7'd45, 4'd9, 8'h00);
        write_weight(7'd45, 4'd9, 8'hA5);
        read_and_check_weight(7'd45, 4'd9, 8'hA5);
        write_weight(7'd46, 4'd10, 8'hFF);
        write_weight(7'd47, 4'd11, 8'h00);
        read_and_check_weight(7'd46, 4'd10, 8'hFF);
        read_and_check_weight(7'd47, 4'd11, 8'h00);
        read_and_check_weight(7'd45, 4'd9, 8'hA5);

        // Start near the end of a row so the burst must carry bank 14, 15,
        // then increment the row and continue at bank 0 without a bubble.
        burst_write_and_check(7'd40, 4'd14, 12'd20);
        for (row_index = 0; row_index < 20; row_index = row_index + 1) begin
            weight_value = (40 * 16) + 14 + row_index;
            read_and_check_weight(weight_value[10:4], weight_value[3:0],
                                  weight_model[weight_value / 16]
                                              [weight_value % 16]);
        end

        // Program all 32 local rows used by an A4W8 calculation in group 0.
        for (row_index = 0; row_index < 32; row_index = row_index + 1) begin
            weight_value = ((row_index * 7) + 35) & 255;
            write_weight(row_index[6:0], 4'd2, weight_value[7:0]);
        end

        // The high nibble is deliberately nonzero garbage.  A4 mode must
        // ignore it and use only activation_flat[row][3:0].
        activation_flat = 256'd0;
        for (row_index = 0; row_index < 32; row_index = row_index + 1) begin
            activation_value = 160 | ((row_index * 5 + 3) & 15);
            activation_flat[(row_index * 8) +: 8] = activation_value[7:0];
        end
        compute_and_check(2'd0, 4'd2, 1'b0);
        read_and_check_weight(7'd0, 4'd2, weight_model[0][2]);

        // Program a different physical group/pair for a full A8W8 case.
        for (row_index = 0; row_index < 32; row_index = row_index + 1) begin
            weight_value = ((row_index * 13) + 81) & 255;
            write_weight((7'd96 + row_index[6:0]), 4'd15, weight_value[7:0]);
        end

        activation_flat = 256'd0;
        for (row_index = 0; row_index < 32; row_index = row_index + 1) begin
            activation_value = ((row_index * 11) + 23) & 255;
            activation_flat[(row_index * 8) +: 8] = activation_value[7:0];
        end
        compute_and_check(2'd3, 4'd15, 1'b1);
        read_and_check_weight(7'd96, 4'd15, weight_model[96][15]);

        // Burst length zero is illegal and must terminate with an error.
        command_burst_length = 12'd0;
        start_command(OP_WEIGHT_BURST);
        wait_for_done();
        if (!error || result_valid) begin
            $display("FAIL: zero-length burst did not report error");
            errors = errors + 1;
        end else begin
            $display("PASS: zero-length burst reports error without result_valid");
        end

        if (errors == 0) begin
            $display("============================================================");
            $display("PASS: dcim_pin_master completed all integration checks");
            $display("============================================================");
            $finish;
        end else begin
            $fatal(1, "FAIL: dcim_pin_master found %0d error(s)", errors);
        end
    end

endmodule
