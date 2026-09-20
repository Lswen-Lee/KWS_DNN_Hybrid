`timescale 1ns/1ps

module tb_sram_write_buffer_8bit;

    logic       sram_path_en;
    logic [3:0] stage0_bits;
    logic [3:0] stage1_bits;
    logic [7:0] write_data;

    integer error_count;

    sram_write_buffer_8bit dut (
        .sram_path_en(sram_path_en),
        .stage0_bits (stage0_bits),
        .stage1_bits (stage1_bits),
        .write_data  (write_data)
    );

    initial begin
        sram_path_en = 1'b0;
        stage0_bits  = 4'h1;
        stage1_bits  = 4'h9;
        error_count  = 0;

        $display("============================================================");
        $display("Testbench : tb_sram_write_buffer_8bit");
        $display("Function  : combine slide-3 DFF stage 1 and stage 0 taps");
        $display("Ordering  : write_data = {stage1_bits, stage0_bits}");
        $display("============================================================");

        // Test 1: the inactive demux branch must output zero.
        #1;
        if (write_data !== 8'h00) begin
            $display("FAIL: disabled SRAM path expected 00, actual=%02h", write_data);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 1 - disabled SRAM path outputs zero");
        end

        // Test 2: slide-12 example, first nibble 9 followed by nibble 1.
        sram_path_en = 1'b1;
        #1;
        if (write_data !== 8'h91) begin
            $display("FAIL: stage1=9 and stage0=1 expected 91, actual=%02h",
                     write_data);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 2 - stage1=9 and stage0=1 form 8'h91");
        end

        // Test 3: another pattern confirms nibble ordering is not reversed.
        stage1_bits = 4'ha;
        stage0_bits = 4'h5;
        #1;
        if (write_data !== 8'ha5) begin
            $display("FAIL: stage1=a and stage0=5 expected a5, actual=%02h",
                     write_data);
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 3 - high/low nibble ordering is correct");
        end

        // Test 4: route disable does not require a clock because this is the
        // combinational mode demux after the already existing DFF stages.
        sram_path_en = 1'b0;
        #1;
        if (write_data !== 8'h00) begin
            $display("FAIL: route disable did not return write_data to zero");
            error_count = error_count + 1;
        end else begin
            $display("PASS: Test 4 - route disable immediately isolates the path");
        end

        $display("============================================================");
        if (error_count == 0) begin
            $display("PASS: all SRAM write-buffer tests passed");
        end else begin
            $display("FAIL: %0d SRAM write-buffer checks failed", error_count);
            $fatal(1);
        end
        $display("============================================================");

        $finish;
    end

endmodule
