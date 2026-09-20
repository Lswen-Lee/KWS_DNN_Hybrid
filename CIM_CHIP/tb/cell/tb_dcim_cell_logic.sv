`timescale 1ns/1ps

module tb_dcim_cell_logic;

    integer weight_value;
    integer check_count;

    logic clk = 1'b0;
    logic rst_n;
    logic write_en;
    logic write_data;
    logic nv_store;
    logic nv_recall;
    logic pd_en;
    logic cim_input_b;
    logic read_q;
    logic read_qb;
    logic cim_product;

    always #5 clk = ~clk;

    dcim_cell_logic dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .write_en       (write_en),
        .write_data     (write_data),
        .nv_store       (nv_store),
        .nv_recall      (nv_recall),
        .pd_en          (pd_en),
        .cim_input_b    (cim_input_b),
        .read_q         (read_q),
        .read_qb        (read_qb),
        .cim_product    (cim_product)
    );

    task automatic write_weight(input logic value);
        $display("[WEIGHT WRITE] Request weight Q=%b", value);
        @(negedge clk);
        write_en   = 1'b1;
        write_data = value;
        @(posedge clk);
        #1;
        write_en = 1'b0;
        $display("               t=%0.1f ns | stored Q=%b QB=%b | expected Q=%b QB=%b",
                 $realtime, read_q, read_qb, value, ~value);
    endtask

    task automatic check_product(
        input logic input_b_value,
        input logic expected_value,
        input string step_name
    );
        cim_input_b = input_b_value;
        #1;
        check_count++;
        $display("[DCIM CHECK %0d] %-28s | Q=%b QB=%b | IN_b=%b | expected NOR=%b actual=%b",
                 check_count, step_name, read_q, read_qb, cim_input_b,
                 expected_value, cim_product);
        assert (cim_product === expected_value)
            else $fatal(1, "%s: product=%b, expected=%b",
                        step_name, cim_product, expected_value);
    endtask

    initial begin
        rst_n          = 1'b0;
        write_en       = 1'b0;
        write_data     = 1'b0;
        nv_store       = 1'b0;
        nv_recall      = 1'b0;
        pd_en          = 1'b0;
        cim_input_b    = 1'b1;
        check_count     = 0;

        $display("================================================================================================================");
        $display("Testbench : tb_dcim_cell_logic");
        $display("Purpose   : verify one storage bit and its per-cell NOR compute path");
        $display("Boundary  : shared Input Control generates IN_b outside this cell");
        $display("Equation  : product = ~(IN_b | QB)");
        $display("Columns   : stored nodes, active-low compute input, expected and actual output");
        $display("================================================================================================================\n");

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        #1;

        // Exhaust all two stored weights and both active-low compute inputs.
        for (weight_value = 0; weight_value < 2; weight_value++) begin
            write_weight(weight_value[0]);
            assert (read_q === weight_value[0] &&
                    read_qb === ~weight_value[0])
                else $fatal(1, "SRAM complementary nodes are incorrect");
            $display("               weight-node check: PASS\n");

            check_product(1'b1, 1'b0,
                          $sformatf("weight=%0d, IN_b=1", weight_value));
            check_product(1'b0, weight_value[0],
                          $sformatf("weight=%0d, IN_b=0", weight_value));
        end

        $display("================================================================================================================");
        $display("PASS: tb_dcim_cell_logic completed %0d exhaustive checks", check_count);
        $display("================================================================================================================");
        $finish;
    end

endmodule
