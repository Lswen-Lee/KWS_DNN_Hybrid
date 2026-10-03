`timescale 1ns/1ps
module tb_activation_buffer;
    import kws_system_pkg::*;
    logic clk = 0;
    always #5 clk = ~clk;
    logic rst = 1, wr_en = 0, rd_en = 0;
    activation_addr_t wr_addr = 0, rd_addr = 0;
    activation_t wr_data = 0, rd_data;
    logic rd_valid;
    activation_t reference_mem [0:ACT_DEPTH-1];
    bit initialized [0:ACT_DEPTH-1];
    integer checks = 0;
    integer reads = 0;
    integer writes = 0;
    logic [31:0] rng = 32'h5052026;
    integer wa, ra;
    bit we, re;
    activation_buffer dut (.*);

    // Drive at falling edge, check both before and after the active edge.
    // The scoreboard uses only public ports, never the DUT memory hierarchy.
    task automatic cycle(input bit reset_value, input bit write_enable,
                         input integer write_address, input activation_t data,
                         input bit read_enable, input integer read_address);
        activation_t expected_data, previous_data;
        logic previous_valid;
        begin
            if (write_address < 0 || write_address >= ACT_DEPTH ||
                read_address < 0 || read_address >= ACT_DEPTH)
                $fatal(1, "TB address outside memory range");
            @(negedge clk);
            previous_data = rd_data;
            previous_valid = rd_valid;
            rst = reset_value;
            wr_en = write_enable;
            wr_addr = activation_addr_t'(write_address);
            wr_data = data;
            rd_en = read_enable;
            rd_addr = activation_addr_t'(read_address);
            if (!reset_value && read_enable) begin
                if (!initialized[read_address]) $fatal(1, "TB attempted uninitialized read");
                expected_data = reference_mem[read_address];
            end
            #1;
            if (rd_valid !== previous_valid || rd_data !== previous_data)
                $fatal(1, "Output changed before rising edge");
            @(posedge clk);
            #1;
            checks++;
            if (rd_valid !== (!reset_value && read_enable))
                $fatal(1, "rd_valid mismatch at check %0d", checks);
            if (!reset_value && read_enable) begin
                reads++;
                if (rd_data !== expected_data)
                    $fatal(1, "Read mismatch address=%0d expected=%h actual=%h", read_address, expected_data, rd_data);
            end else if (rd_data !== previous_data)
                $fatal(1, "Read data must hold without accepted read");
            if (!reset_value && write_enable) begin
                reference_mem[write_address] = data;
                initialized[write_address] = 1;
                writes++;
            end
        end
    endtask

    initial begin
        if ($bits(activation_t) != 8 || $bits(activation_addr_t) != 15 ||
            $bits(activation_count_t) != 16 || ACT_DEPTH != 32768 || ACT_ZERO_POINT != 128 ||
            READ_LINEAR == READ_PATCH || WRITE_LINEAR == WRITE_CHW)
            $fatal(1, "Package contract mismatch");
        cycle(1, 0, 0, 0, 0, 0);
        if ($test$plusargs("collision")) begin
            $display("Negative test: same-address simultaneous read/write must fail");
            @(negedge clk);
            rst = 0; wr_en = 1; rd_en = 1; wr_addr = 42; rd_addr = 42;
            @(posedge clk); #1;
            $fatal(1, "Collision was NOT detected");
        end
        $display("[1] Basic write/read and UINT8 boundaries");
        cycle(0, 1, 100, 8'ha5, 0, 0);
        cycle(0, 0, 0, 0, 1, 100);
        for (integer i = 0; i < 4; i++) begin
            case (i)
                0: cycle(0, 1, i, 8'h00, 0, 0);
                1: cycle(0, 1, i, 8'h7f, 0, 0);
                2: cycle(0, 1, i, 8'h80, 0, 0);
                3: cycle(0, 1, i, 8'hff, 0, 0);
            endcase
            cycle(0, 0, 0, 0, 1, i);
        end
        $display("[2] Fill and read all 32768 addresses (including endpoints)");
        for (integer i = 0; i < ACT_DEPTH; i++)
            cycle(0, 1, i, activation_t'(i ^ (i >> 8)), 0, 0);
        for (integer i = 0; i < ACT_DEPTH; i++)
            cycle(0, 0, 0, 0, 1, i);
        $display("[3] Simultaneous different-address read/write and bubbles");
        for (integer i = 0; i < 128; i++)
            cycle(0, 1, i, activation_t'(255-i), 1, ACT_DEPTH-1-i);
        cycle(0, 0, 0, 0, 0, 0);
        $display("[4] Reset blocks transactions and preserves stored contents");
        cycle(1, 1, 100, 8'h11, 1, 100);
        cycle(1, 1, ACT_DEPTH-1, 8'h22, 0, 0);
        cycle(0, 0, 0, 0, 1, 100);
        cycle(0, 0, 0, 0, 1, ACT_DEPTH-1);
        $display("[5] 10000 deterministic mixed transactions (seed 05052026)");
        for (integer i = 0; i < 10000; i++) begin
            rng = rng ^ (rng << 13);
            rng = rng ^ (rng >> 17);
            rng = rng ^ (rng << 5);
            wa = int'(rng[14:0]);
            ra = int'(rng[29:15]);
            we = rng[30]; re = rng[31];
            if (wa == ra) ra = (ra + 1) % ACT_DEPTH;
            cycle(0, we, wa, rng[23:16], re, ra);
        end
        $display("[6] Full memory readback after mixed transactions");
        for (integer i = 0; i < ACT_DEPTH; i++)
            cycle(0, 0, 0, 0, 1, i);
        cycle(0, 0, 0, 0, 0, 0);
        $display("PASS activation_buffer checks=%0d reads=%0d writes=%0d", checks, reads, writes);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "Watchdog timeout");
    end
endmodule
