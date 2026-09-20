`timescale 1ns/1ps

module tb_fesram_cell_model;

    integer check_count;

    logic clk = 1'b0;
    logic rst_n;
    logic write_en;
    logic write_data;
    logic nv_store;
    logic nv_recall;
    logic pd_en;
    logic q;
    logic qb;

    always #5 clk = ~clk;

    fesram_cell_model dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .write_en   (write_en),
        .write_data (write_data),
        .nv_store   (nv_store),
        .nv_recall  (nv_recall),
        .pd_en      (pd_en),
        .q          (q),
        .qb         (qb)
    );

    task automatic drive_cycle(
        input logic next_write_en,
        input logic next_write_data,
        input logic next_nv_store,
        input logic next_nv_recall,
        input logic next_pd_en
    );
        @(negedge clk);
        write_en   = next_write_en;
        write_data = next_write_data;
        nv_store   = next_nv_store;
        nv_recall  = next_nv_recall;
        pd_en      = next_pd_en;
        @(posedge clk);
        #1;
    endtask

    task automatic check_cell(input logic expected_q, input string step_name);
        check_count++;
        $display("[CELL CHECK %0d] t=%0.1f ns | %-38s", check_count, $realtime,
                 step_name);
        $display("                 inputs: rst_n=%b write_en=%b write_data=%b nv_store=%b nv_recall=%b pd_en=%b",
                 rst_n, write_en, write_data, nv_store, nv_recall, pd_en);
        $display("                 actual: Q=%b QB=%b | expected: Q=%b QB=%b",
                 q, qb, expected_q, ~expected_q);
        assert (q === expected_q)
            else $fatal(1, "%s: q=%b, expected=%b", step_name, q, expected_q);
        assert (qb === ~expected_q)
            else $fatal(1, "%s: qb=%b, expected=%b", step_name, qb, ~expected_q);
        $display("                 result: PASS\n");
    endtask

    initial begin
        rst_n      = 1'b0;
        write_en   = 1'b0;
        write_data = 1'b0;
        nv_store   = 1'b0;
        nv_recall  = 1'b0;
        pd_en      = 1'b0;
        check_count = 0;

        $display("============================================================");
        $display("Testbench : tb_fesram_cell_model");
        $display("Purpose   : verify the current one-FF cell storage model");
        $display("Clock     : 10 ns period; controls sampled at posedge clk");
        $display("Rules     : reset -> Q=0; write_en -> Q=write_data;");
        $display("            otherwise Q holds its previous value");
        $display("Reserved  : nv_store/nv_recall/pd_en currently have no effect");
        $display("============================================================\n");

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;
        check_cell(1'b0, "reset");

        drive_cycle(1'b1, 1'b1, 1'b0, 1'b0, 1'b0);
        check_cell(1'b1, "write SRAM=1");

        // Reserved future FeRAM pins must not alter the one-FF model.
        drive_cycle(1'b0, 1'b0, 1'b1, 1'b0, 1'b0);
        check_cell(1'b1, "reserved nv_store has no effect");
        drive_cycle(1'b0, 1'b0, 1'b0, 1'b0, 1'b1);
        check_cell(1'b1, "reserved pd_en has no effect");
        drive_cycle(1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_cell(1'b1, "reserved nv_recall has no effect");

        drive_cycle(1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        check_cell(1'b0, "write SRAM=0");

        // Hold must preserve the most recently programmed weight.
        drive_cycle(1'b0, 1'b1, 1'b0, 1'b0, 1'b0);
        check_cell(1'b0, "hold ignores write_data");

        $display("============================================================");
        $display("PASS: tb_fesram_cell_model completed %0d checks", check_count);
        $display("============================================================");
        $finish;
    end

endmodule
