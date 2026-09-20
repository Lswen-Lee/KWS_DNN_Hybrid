`timescale 1ns/1ps

module tb_dcim_cdc_bridge;

    localparam logic [1:0] OP_WEIGHT_WRITE = 2'd0;
    localparam logic [1:0] OP_SRAM_READ    = 2'd1;
    localparam logic [1:0] OP_CIM_COMPUTE  = 2'd2;

    logic clk_125m = 1'b0;
    logic clk_50m  = 1'b0;
    logic rst_125m;
    logic rst_50m;

    logic         cmd_valid;
    logic         cmd_ready;
    logic [1:0]   cmd_operation;
    logic [6:0]   cmd_row_addr;
    logic [3:0]   cmd_bank_addr;
    logic [7:0]   cmd_weight;
    logic [255:0] cmd_activation_flat;
    logic         cmd_activation_is_a8;

    logic         rsp_valid;
    logic         rsp_ready;
    logic         rsp_data_valid;
    logic         rsp_error;
    logic [7:0]   rsp_sram_read_data;
    logic [17:0]  rsp_even_raw_result;
    logic [17:0]  rsp_odd_raw_result;

    logic         master_start;
    logic [1:0]   master_operation;
    logic [6:0]   master_row_addr;
    logic [3:0]   master_bank_addr;
    logic [7:0]   master_weight;
    logic [255:0] master_activation_flat;
    logic         master_activation_is_a8;
    logic         master_busy;
    logic         master_done;
    logic         master_result_valid;
    logic         master_error;
    logic [7:0]   master_sram_read_data;
    logic [17:0]  master_even_raw_result;
    logic [17:0]  master_odd_raw_result;

    // Expected command retained independently by the testbench so the fast
    // source pins can be deliberately changed immediately after acceptance.
    logic [1:0]   expected_operation;
    logic [6:0]   expected_row_addr;
    logic [3:0]   expected_bank_addr;
    logic [7:0]   expected_weight;
    logic [255:0] expected_activation;
    logic         expected_activation_is_a8;
    logic         mock_protocol_error;

    integer errors;
    integer sent_count;
    integer response_count;
    integer master_start_count;
    integer random_case;
    integer random_word;
    integer generated_row;
    integer generated_bank;
    integer generated_weight;
    integer mock_delay_count;
    logic [255:0] random_activation;

    // 125 MHz clock: 8 ns period.
    always #4 clk_125m = ~clk_125m;

    // 50 MHz clock: 20 ns period with a deliberate 3 ns phase offset.
    initial begin
        #3;
        forever #10 clk_50m = ~clk_50m;
    end

    function automatic logic [7:0] make_read_result(
        input logic [6:0] row_value,
        input logic [3:0] bank_value,
        input logic [7:0] weight_value
    );
        begin
            make_read_result = weight_value ^ {1'b0, row_value} ^
                               {4'b0000, bank_value};
        end
    endfunction

    function automatic logic [17:0] make_even_result(
        input logic [6:0] row_value,
        input logic [3:0] bank_value,
        input logic [7:0] weight_value,
        input logic [255:0] activation_value
    );
        begin
            make_even_result = activation_value[17:0] ^
                               {11'd0, row_value} ^
                               {14'd0, bank_value} ^
                               {10'd0, weight_value};
        end
    endfunction

    function automatic logic [17:0] make_odd_result(
        input logic [6:0] row_value,
        input logic [3:0] bank_value,
        input logic [7:0] weight_value,
        input logic [255:0] activation_value
    );
        begin
            make_odd_result = activation_value[35:18] ^
                              {11'd0, row_value} ^
                              {14'd0, bank_value} ^
                              {10'd0, weight_value};
        end
    endfunction

    dcim_cdc_bridge dut (
        .clk_125m                 (clk_125m),
        .rst_125m                 (rst_125m),
        .cmd_valid                (cmd_valid),
        .cmd_ready                (cmd_ready),
        .cmd_operation            (cmd_operation),
        .cmd_row_addr             (cmd_row_addr),
        .cmd_bank_addr            (cmd_bank_addr),
        .cmd_weight               (cmd_weight),
        .cmd_activation_flat      (cmd_activation_flat),
        .cmd_activation_is_a8     (cmd_activation_is_a8),
        .rsp_valid                (rsp_valid),
        .rsp_ready                (rsp_ready),
        .rsp_data_valid           (rsp_data_valid),
        .rsp_error                (rsp_error),
        .rsp_sram_read_data       (rsp_sram_read_data),
        .rsp_even_raw_result      (rsp_even_raw_result),
        .rsp_odd_raw_result       (rsp_odd_raw_result),
        .clk_50m                  (clk_50m),
        .rst_50m                  (rst_50m),
        .master_start             (master_start),
        .master_operation         (master_operation),
        .master_row_addr          (master_row_addr),
        .master_bank_addr         (master_bank_addr),
        .master_weight            (master_weight),
        .master_activation_flat   (master_activation_flat),
        .master_activation_is_a8  (master_activation_is_a8),
        .master_busy              (master_busy),
        .master_done              (master_done),
        .master_result_valid      (master_result_valid),
        .master_error             (master_error),
        .master_sram_read_data    (master_sram_read_data),
        .master_even_raw_result   (master_even_raw_result),
        .master_odd_raw_result    (master_odd_raw_result)
    );

    // Variable-latency mock of dcim_pin_master.  It checks all 278 command
    // bits at the slow-domain start pulse, then creates deterministic results.
    always_ff @(posedge clk_50m or posedge rst_50m) begin
        if (rst_50m) begin
            master_busy            <= 1'b0;
            master_done            <= 1'b0;
            master_result_valid    <= 1'b0;
            master_error           <= 1'b0;
            master_sram_read_data  <= 8'd0;
            master_even_raw_result <= 18'd0;
            master_odd_raw_result  <= 18'd0;
            mock_delay_count       <= 0;
            master_start_count     <= 0;
            mock_protocol_error    <= 1'b0;
        end else begin
            master_done <= 1'b0;

            if (master_start) begin
                master_start_count <= master_start_count + 1;
                if (master_busy)
                    mock_protocol_error <= 1'b1;

                if ((master_operation       !== expected_operation) ||
                    (master_row_addr        !== expected_row_addr) ||
                    (master_bank_addr       !== expected_bank_addr) ||
                    (master_weight          !== expected_weight) ||
                    (master_activation_flat !== expected_activation) ||
                    (master_activation_is_a8 !== expected_activation_is_a8)) begin
                    mock_protocol_error <= 1'b1;
                end

                master_busy         <= 1'b1;
                mock_delay_count    <= 2 + {30'd0, master_bank_addr[1:0]};
                master_result_valid <= (master_operation == OP_SRAM_READ) ||
                                       (master_operation == OP_CIM_COMPUTE);
                master_error        <= (master_operation == 2'd3);
                master_sram_read_data <= make_read_result(
                    master_row_addr, master_bank_addr, master_weight);
                master_even_raw_result <= make_even_result(
                    master_row_addr, master_bank_addr, master_weight,
                    master_activation_flat);
                master_odd_raw_result <= make_odd_result(
                    master_row_addr, master_bank_addr, master_weight,
                    master_activation_flat);
            end else if (master_busy) begin
                if (mock_delay_count == 0) begin
                    master_busy <= 1'b0;
                    master_done <= 1'b1;
                end else begin
                    mock_delay_count <= mock_delay_count - 1;
                end
            end
        end
    end

    task automatic issue_and_check(
        input logic [1:0]   operation_value,
        input logic [6:0]   row_value,
        input logic [3:0]   bank_value,
        input logic [7:0]   weight_value,
        input logic [255:0] activation_value,
        input logic         activation_is_a8_value,
        input integer       response_hold_cycles
    );
        logic        expected_data_valid_value;
        logic        expected_error_value;
        logic [7:0]  expected_read_value;
        logic [17:0] expected_even_value;
        logic [17:0] expected_odd_value;
        logic        saved_data_valid;
        logic        saved_error;
        logic [7:0]  saved_read;
        logic [17:0] saved_even;
        logic [17:0] saved_odd;
        integer hold_index;
        begin
            while (!cmd_ready) begin
                @(posedge clk_125m);
                #1;
            end

            @(negedge clk_125m);
            expected_operation        = operation_value;
            expected_row_addr         = row_value;
            expected_bank_addr        = bank_value;
            expected_weight           = weight_value;
            expected_activation       = activation_value;
            expected_activation_is_a8 = activation_is_a8_value;

            cmd_operation        = operation_value;
            cmd_row_addr         = row_value;
            cmd_bank_addr        = bank_value;
            cmd_weight           = weight_value;
            cmd_activation_flat  = activation_value;
            cmd_activation_is_a8 = activation_is_a8_value;
            cmd_valid            = 1'b1;

            @(posedge clk_125m);
            #1;
            sent_count = sent_count + 1;

            @(negedge clk_125m);
            cmd_valid            = 1'b0;

            // Deliberately corrupt the source pins.  The slow side must still
            // receive the values captured in the bridge command mailbox.
            cmd_operation        = ~operation_value;
            cmd_row_addr         = ~row_value;
            cmd_bank_addr        = ~bank_value;
            cmd_weight           = ~weight_value;
            cmd_activation_flat  = ~activation_value;
            cmd_activation_is_a8 = ~activation_is_a8_value;

            while (!rsp_valid) begin
                @(posedge clk_125m);
                #1;
                if (cmd_ready) begin
                    $display("FAIL: cmd_ready rose before outstanding response");
                    errors = errors + 1;
                end
            end

            expected_data_valid_value =
                (operation_value == OP_SRAM_READ) ||
                (operation_value == OP_CIM_COMPUTE);
            expected_error_value = operation_value == 2'd3;
            expected_read_value  = make_read_result(
                row_value, bank_value, weight_value);
            expected_even_value  = make_even_result(
                row_value, bank_value, weight_value, activation_value);
            expected_odd_value   = make_odd_result(
                row_value, bank_value, weight_value, activation_value);

            if ((rsp_data_valid      !== expected_data_valid_value) ||
                (rsp_error           !== expected_error_value) ||
                (rsp_sram_read_data  !== expected_read_value) ||
                (rsp_even_raw_result !== expected_even_value) ||
                (rsp_odd_raw_result  !== expected_odd_value)) begin
                $display("FAIL: response mismatch for command %0d", sent_count);
                errors = errors + 1;
            end

            saved_data_valid = rsp_data_valid;
            saved_error      = rsp_error;
            saved_read       = rsp_sram_read_data;
            saved_even       = rsp_even_raw_result;
            saved_odd        = rsp_odd_raw_result;

            // Backpressure: response and payload must remain asserted/stable.
            for (hold_index = 0; hold_index < response_hold_cycles;
                 hold_index = hold_index + 1) begin
                @(posedge clk_125m);
                #1;
                if (!rsp_valid || cmd_ready ||
                    (rsp_data_valid      !== saved_data_valid) ||
                    (rsp_error           !== saved_error) ||
                    (rsp_sram_read_data  !== saved_read) ||
                    (rsp_even_raw_result !== saved_even) ||
                    (rsp_odd_raw_result  !== saved_odd)) begin
                    $display("FAIL: response changed while rsp_ready was low");
                    errors = errors + 1;
                end
            end

            @(negedge clk_125m);
            rsp_ready = 1'b1;
            @(posedge clk_125m);
            #1;
            response_count = response_count + 1;
            @(negedge clk_125m);
            rsp_ready = 1'b0;
        end
    endtask

    initial begin
        rst_125m             = 1'b1;
        rst_50m              = 1'b1;
        cmd_valid            = 1'b0;
        cmd_operation        = 2'd0;
        cmd_row_addr         = 7'd0;
        cmd_bank_addr        = 4'd0;
        cmd_weight           = 8'd0;
        cmd_activation_flat  = 256'd0;
        cmd_activation_is_a8 = 1'b0;
        rsp_ready            = 1'b0;
        expected_operation   = 2'd0;
        expected_row_addr    = 7'd0;
        expected_bank_addr   = 4'd0;
        expected_weight      = 8'd0;
        expected_activation  = 256'd0;
        expected_activation_is_a8 = 1'b0;
        random_activation    = 256'd0;
        errors               = 0;
        sent_count           = 0;
        response_count       = 0;

        $display("============================================================");
        $display("Testbench : tb_dcim_cdc_bridge");
        $display("Purpose   : verify 125/50 MHz toggle-mailbox CDC protocol");
        $display("============================================================");

        repeat (5) @(posedge clk_125m);
        repeat (3) @(posedge clk_50m);
        @(negedge clk_125m);
        rst_125m = 1'b0;
        @(negedge clk_50m);
        rst_50m = 1'b0;

        // No reset transition may create a phantom slow-domain command.
        repeat (8) @(posedge clk_50m);
        #1;
        if (master_start_count != 0) begin
            $display("FAIL: reset created a phantom command");
            errors = errors + 1;
        end else begin
            $display("PASS: reset/toggle alignment creates no phantom command");
        end

        issue_and_check(OP_WEIGHT_WRITE, 7'd45, 4'd9, 8'hA5,
                        256'h0123_4567_89ab_cdef_0011_2233_4455_6677_8899_aabb_ccdd_eeff_1357_9bdf_2468_ace0,
                        1'b0, 0);
        issue_and_check(OP_SRAM_READ, 7'd12, 4'd3, 8'h7E,
                        256'hffff_0000_aaaa_5555_1234_5678_9abc_def0_0f0f_f0f0_3333_cccc_55aa_aa55_8765_4321,
                        1'b0, 3);
        issue_and_check(OP_CIM_COMPUTE, 7'd96, 4'd15, 8'hC3,
                        256'h0011_2233_4455_6677_8899_aabb_ccdd_eeff_fedc_ba98_7654_3210_1357_2468_aaaa_5555,
                        1'b1, 5);
        issue_and_check(2'd3, 7'd127, 4'd0, 8'h00, 256'd0,
                        1'b0, 2);

        // Repeated randomized payloads exercise both toggle polarities and
        // different phase relationships over many transactions.
        for (random_case = 0; random_case < 32;
             random_case = random_case + 1) begin
            for (random_word = 0; random_word < 8;
                 random_word = random_word + 1)
                random_activation[(random_word * 32) +: 32] = $urandom;

            generated_row    = ((random_case * 17) + 5) & 127;
            generated_bank   = ((random_case * 7) + 1) & 15;
            generated_weight = ((random_case * 29) + 49) & 255;

            issue_and_check(random_case[1:0],
                            generated_row[6:0],
                            generated_bank[3:0],
                            generated_weight[7:0],
                            random_activation,
                            random_case[0], random_case % 6);
        end

        if (mock_protocol_error) begin
            $display("FAIL: mock master observed duplicate start or corrupt command");
            errors = errors + 1;
        end
        if ((sent_count != response_count) ||
            (sent_count != master_start_count)) begin
            $display("FAIL: count mismatch sent=%0d start=%0d response=%0d",
                     sent_count, master_start_count, response_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: %0d commands crossed once with stable responses",
                     sent_count);
            $display("============================================================");
            $finish;
        end else begin
            $fatal(1, "FAIL: dcim_cdc_bridge found %0d error(s)", errors);
        end
    end

    initial begin
        #500000;
        $fatal(1, "FAIL: dcim_cdc_bridge watchdog timeout");
    end

endmodule
