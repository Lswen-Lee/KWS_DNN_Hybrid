`timescale 1ns/1ps

module tb_dcim_row_4bit;

    integer weight_value;
    integer control_vector;
    integer check_count;

    logic       clk = 1'b0;
    logic       rst_n;
    logic       row_write_en;
    logic [3:0] write_data;
    logic       sense_en;
    logic [3:0] read_data;
    logic       nv_store;
    logic       nv_recall;
    logic       pd_en;
    logic       cim_en;
    logic       cim_row;
    logic       activation_bit;
    logic [3:0] stored_q;
    logic [3:0] stored_qb;
    logic [3:0] row_product;

    always #5 clk = ~clk;

    dcim_row_4bit dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .row_write_en   (row_write_en),
        .write_data     (write_data),
        .sense_en       (sense_en),
        .read_data      (read_data),
        .nv_store       (nv_store),
        .nv_recall      (nv_recall),
        .pd_en          (pd_en),
        .cim_en         (cim_en),
        .cim_row        (cim_row),
        .activation_bit (activation_bit),
        .stored_q       (stored_q),
        .stored_qb      (stored_qb),
        .row_product    (row_product)
    );

    task automatic write_weight(input logic [3:0] value);
        @(negedge clk);
        row_write_en = 1'b1;
        write_data   = value;
        @(posedge clk);
        #1;
        row_write_en = 1'b0;

        assert (stored_q === value)
            else $fatal(1, "write failed: Q=%04b, expected=%04b",
                        stored_q, value);
        assert (stored_qb === ~value)
            else $fatal(1, "complement failed: QB=%04b, expected=%04b",
                        stored_qb, ~value);

        // Direct SRAM readback without precharge or a clocked sense phase.
        sense_en = 1'b1;
        #1;
        assert (read_data === value)
            else $fatal(1, "readback failed: data=%04b, expected=%04b",
                        read_data, value);
        sense_en = 1'b0;
        #1;
        assert (read_data === 4'b0000)
            else $fatal(1, "disabled read must output zero, actual=%04b",
                        read_data);

        $display("[WRITE] weight=%2d (0x%1h/%04b) | Q=%04b QB=%04b | bit significance={8,4,2,1}",
                 value, value, value, stored_q, stored_qb);
    endtask

    task automatic check_row_product(
        input logic       en_value,
        input logic       row_value,
        input logic       activation_value,
        input logic [3:0] expected_value
    );
        cim_en         = en_value;
        cim_row        = row_value;
        activation_bit = activation_value;
        #1;
        check_count++;

        $display("[CHECK %3d] W=%2d/%04b | en=%b row=%b act=%b -> IN_b=%b | expected=%04b (%2d) actual=%04b (%2d)",
                 check_count, stored_q, stored_q, cim_en, cim_row,
                 activation_bit, dut.cim_input_b, expected_value,
                 expected_value, row_product, row_product);

        assert (row_product === expected_value)
            else $fatal(1,
                        "row product mismatch: W=%04b en=%b row=%b act=%b actual=%04b expected=%04b",
                        stored_q, cim_en, cim_row, activation_bit,
                        row_product, expected_value);
    endtask

    initial begin
        rst_n          = 1'b0;
        row_write_en   = 1'b0;
        write_data     = 4'b0000;
        sense_en       = 1'b0;
        nv_store       = 1'b0;
        nv_recall      = 1'b0;
        pd_en          = 1'b0;
        cim_en         = 1'b0;
        cim_row        = 1'b0;
        activation_bit = 1'b0;
        check_count     = 0;

        $display("================================================================================================================");
        $display("Testbench : tb_dcim_row_4bit");
        $display("Structure : four one-bit cells store one unsigned 4-bit weight; write_data[3] is MSB");
        $display("Equation  : IN_b = ~(cim_en & cim_row & activation_bit)");
        $display("            row_product[k] = ~(IN_b | stored_qb[k])");
        $display("Expected  : controls all 1 -> stored weight; otherwise -> 0000");
        $display("Read path : sense_en=1 exposes the stored weight to the bank sense path");
        $display("Coverage  : 16 write/readbacks x all 8 control combinations = 128 compute checks");
        $display("================================================================================================================\n");

        repeat (2) @(posedge clk);
        #1;
        assert (stored_q === 4'b0000 && stored_qb === 4'b1111)
            else $fatal(1, "reset state is incorrect: Q=%04b QB=%04b",
                        stored_q, stored_qb);
        sense_en = 1'b1;
        #1;
        assert (read_data === 4'b0000)
            else $fatal(1, "reset readback is incorrect: data=%04b", read_data);
        sense_en = 1'b0;
        $display("[RESET] Q=%04b QB=%04b : PASS\n", stored_q, stored_qb);
        rst_n = 1'b1;

        // Every possible 4-bit weight also checks 0001/0010/0100/1000 bit order.
        for (weight_value = 0; weight_value < 16; weight_value++) begin
            write_weight(weight_value[3:0]);

            for (control_vector = 0;
                 control_vector < 8;
                 control_vector++) begin
                check_row_product(
                    control_vector[2],
                    control_vector[1],
                    control_vector[0],
                    (control_vector[2:0] == 3'b111) ?
                    weight_value[3:0] : 4'b0000
                );
            end
            $display("");
        end

        // A disabled write must hold the previous programmed weight.
        @(negedge clk);
        row_write_en = 1'b0;
        write_data   = 4'b0000;
        nv_store     = 1'b1;
        nv_recall    = 1'b1;
        pd_en        = 1'b1;
        @(posedge clk);
        #1;
        assert (stored_q === 4'b1111)
            else $fatal(1, "hold/reserved-control check changed Q=%04b", stored_q);
        $display("[HOLD] write_en=0 and reserved controls=1 keep Q=%04b : PASS",
                 stored_q);

        $display("================================================================================================================");
        $display("PASS: tb_dcim_row_4bit completed 16 writes and %0d exhaustive compute checks",
                 check_count);
        $display("================================================================================================================");
        $finish;
    end

endmodule
