`timescale 1ns/1ps

module tb_cim_group_decoder_2to4;

    logic [1:0] group_addr;
    logic [3:0] cim_row;

    logic [3:0] expected_cim_row;
    integer address_index;
    integer bit_index;
    integer selected_count;
    integer error_count;

    cim_group_decoder_2to4 dut (
        .group_addr (group_addr),
        .cim_row    (cim_row)
    );

    initial begin
        group_addr      = 2'b00;
        expected_cim_row = 4'b0001;
        error_count     = 0;

        $display("============================================================");
        $display("Testbench : tb_cim_group_decoder_2to4");
        $display("Purpose   : select one of four 32-row DCIM groups");
        $display("Input     : group_addr = {A6, A5}");
        $display("Mapping   : 00->rows 0..31, 01->32..63,");
        $display("            10->rows 64..95, 11->96..127");
        $display("============================================================");

        // Exhaustively test all four possible two-bit addresses.
        for (address_index = 0; address_index < 4; address_index = address_index + 1) begin
            group_addr = address_index[1:0];
            #1;

            expected_cim_row = 4'b0000;
            expected_cim_row[address_index] = 1'b1;

            $display("Address %02b selects cim_row=%04b (global rows %0d..%0d)",
                     group_addr, cim_row, address_index * 32,
                     (address_index * 32) + 31);

            if (cim_row !== expected_cim_row) begin
                $display("FAIL: expected cim_row=%04b, actual=%04b",
                         expected_cim_row, cim_row);
                error_count = error_count + 1;
            end

            selected_count = 0;
            for (bit_index = 0; bit_index < 4; bit_index = bit_index + 1) begin
                if (cim_row[bit_index] === 1'b1)
                    selected_count = selected_count + 1;
            end

            if (selected_count != 1) begin
                $display("FAIL: address %02b enabled %0d groups instead of one",
                         group_addr, selected_count);
                error_count = error_count + 1;
            end
        end

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all four CIM group addresses are correct and one-hot");
        end else begin
            $display("FAIL: %0d CIM group decoder checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
