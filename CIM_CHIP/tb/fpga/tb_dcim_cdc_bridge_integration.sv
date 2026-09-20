`timescale 1ns/1ps

module tb_dcim_cdc_bridge_integration;

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
    logic         unused_burst_weight_ready;
    logic [6:0]   unused_burst_weight_row_addr;
    logic [3:0]   unused_burst_weight_bank_addr;
    logic         master_busy;
    logic         master_done;
    logic         master_result_valid;
    logic         master_error;
    logic [7:0]   master_sram_read_data;
    logic [17:0]  master_even_raw_result;
    logic [17:0]  master_odd_raw_result;

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

    integer errors;
    integer master_start_count;
    integer actual_w8;
    logic [255:0] test_activation;

    always #4 clk_125m = ~clk_125m;

    initial begin
        #3;
        forever #10 clk_50m = ~clk_50m;
    end

    dcim_cdc_bridge bridge (
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

    dcim_pin_master master (
        .clk                    (clk_50m),
        .rst                    (rst_50m),
        .start                  (master_start),
        .operation              (master_operation),
        .command_row_addr       (master_row_addr),
        .command_bank_addr      (master_bank_addr),
        .command_weight         (master_weight),
        .activation_flat        (master_activation_flat),
        .activation_is_a8       (master_activation_is_a8),
        // The existing single-command CDC mailbox does not stream bursts.
        // The legacy CDC mailbox has no burst stream, so length zero makes
        // operation 3 explicitly unsupported through this path.
        .command_burst_length   (12'd0),
        .burst_weight_valid     (1'b0),
        .burst_weight_data      (8'd0),
        .burst_weight_ready     (unused_burst_weight_ready),
        .burst_weight_row_addr  (unused_burst_weight_row_addr),
        .burst_weight_bank_addr (unused_burst_weight_bank_addr),
        .busy                   (master_busy),
        .done                   (master_done),
        .result_valid           (master_result_valid),
        .error                  (master_error),
        .sram_read_data         (master_sram_read_data),
        .even_raw_result        (master_even_raw_result),
        .odd_raw_result         (master_odd_raw_result),
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
        .clk         (clk_50m),
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

    always_ff @(posedge clk_50m or posedge rst_50m) begin
        if (rst_50m)
            master_start_count <= 0;
        else if (master_start)
            master_start_count <= master_start_count + 1;
    end

    task automatic transact(
        input logic [1:0]   operation_value,
        input logic [6:0]   row_value,
        input logic [3:0]   bank_value,
        input logic [7:0]   weight_value,
        input logic [255:0] activation_value,
        input logic         activation_is_a8_value
    );
        begin
            while (!cmd_ready) begin
                @(posedge clk_125m);
                #1;
            end

            @(negedge clk_125m);
            cmd_operation        = operation_value;
            cmd_row_addr         = row_value;
            cmd_bank_addr        = bank_value;
            cmd_weight           = weight_value;
            cmd_activation_flat  = activation_value;
            cmd_activation_is_a8 = activation_is_a8_value;
            cmd_valid            = 1'b1;

            @(posedge clk_125m);
            #1;
            @(negedge clk_125m);
            cmd_valid = 1'b0;

            while (!rsp_valid) begin
                @(posedge clk_125m);
                #1;
            end
        end
    endtask

    task automatic consume_response;
        begin
            @(negedge clk_125m);
            rsp_ready = 1'b1;
            @(posedge clk_125m);
            #1;
            @(negedge clk_125m);
            rsp_ready = 1'b0;
        end
    endtask

    task automatic write_and_check(
        input logic [6:0] address,
        input logic [3:0] pair_address,
        input logic [7:0] weight_value
    );
        begin
            transact(OP_WEIGHT_WRITE, address, pair_address, weight_value,
                     256'd0, 1'b0);
            if (rsp_error || rsp_data_valid) begin
                $display("FAIL: write response A=%0d B=%0d", address,
                         pair_address);
                errors = errors + 1;
            end
            consume_response();
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
        errors               = 0;
        actual_w8            = 0;
        test_activation      = 256'd0;

        $display("============================================================");
        $display("Testbench : tb_dcim_cdc_bridge_integration");
        $display("Path      : 125 MHz bridge -> 50 MHz master -> real chip top");
        $display("============================================================");

        repeat (5) @(posedge clk_125m);
        repeat (3) @(posedge clk_50m);
        @(negedge clk_125m);
        rst_125m = 1'b0;
        @(negedge clk_50m);
        rst_50m = 1'b0;

        // Program two rows in group 0, pair 0.
        write_and_check(7'd0, 4'd0, 8'h21);
        write_and_check(7'd1, 4'd0, 8'h43);

        // Verify that the SRAM serial result survives both clock crossings.
        transact(OP_SRAM_READ, 7'd0, 4'd0, 8'd0, 256'd0, 1'b0);
        if (rsp_error || !rsp_data_valid ||
            (rsp_sram_read_data !== 8'h21)) begin
            $display("FAIL: CDC SRAM read expected=0x21 actual=0x%02h",
                     rsp_sram_read_data);
            errors = errors + 1;
        end else begin
            $display("PASS: CDC SRAM write/read returned 0x21");
        end
        consume_response();

        // A4 uses only the low nibble.  High nibbles F/E are intentional.
        test_activation = 256'd0;
        test_activation[7:0]  = 8'hF3;
        test_activation[15:8] = 8'hE2;
        transact(OP_CIM_COMPUTE, 7'd0, 4'd0, 8'd0,
                 test_activation, 1'b0);
        actual_w8 = {14'd0, rsp_odd_raw_result} +
                    ({14'd0, rsp_even_raw_result} << 4);
        if (rsp_error || !rsp_data_valid ||
            (rsp_even_raw_result != 18'd14) ||
            (rsp_odd_raw_result != 18'd9) ||
            (actual_w8 != 233)) begin
            $display("FAIL: CDC A4W8 E=%0d O=%0d W8=%0d",
                     rsp_even_raw_result, rsp_odd_raw_result, actual_w8);
            errors = errors + 1;
        end else begin
            $display("PASS: CDC A4W8 even=14 odd=9 W8=233");
        end
        consume_response();

        // A8 uses all bits of the same 32-byte activation vector.
        test_activation = 256'd0;
        test_activation[7:0]  = 8'd130;
        test_activation[15:8] = 8'd200;
        transact(OP_CIM_COMPUTE, 7'd0, 4'd0, 8'd0,
                 test_activation, 1'b1);
        actual_w8 = {14'd0, rsp_odd_raw_result} +
                    ({14'd0, rsp_even_raw_result} << 4);
        if (rsp_error || !rsp_data_valid ||
            (rsp_even_raw_result != 18'd1060) ||
            (rsp_odd_raw_result != 18'd730) ||
            (actual_w8 != 17690)) begin
            $display("FAIL: CDC A8W8 E=%0d O=%0d W8=%0d",
                     rsp_even_raw_result, rsp_odd_raw_result, actual_w8);
            errors = errors + 1;
        end else begin
            $display("PASS: CDC A8W8 even=1060 odd=730 W8=17690");
        end
        consume_response();

        transact(2'd3, 7'd0, 4'd0, 8'd0, 256'd0, 1'b0);
        if (!rsp_error || rsp_data_valid) begin
            $display("FAIL: unsupported CDC burst status did not cross correctly");
            errors = errors + 1;
        end else begin
            $display("PASS: unsupported CDC burst returns error across CDC");
        end
        consume_response();

        if (master_start_count != 6) begin
            $display("FAIL: expected 6 master starts, observed %0d",
                     master_start_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("============================================================");
            $display("PASS: full CDC/master/chip integration is correct");
            $display("============================================================");
            $finish;
        end else begin
            $fatal(1, "FAIL: CDC integration found %0d error(s)", errors);
        end
    end

    initial begin
        #1000000;
        $fatal(1, "FAIL: CDC integration watchdog timeout");
    end

endmodule
