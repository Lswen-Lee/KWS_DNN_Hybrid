`timescale 1ns/1ps
module tb_pe8_result_correction;
    logic clk = 0;
    always #4 clk = ~clk;
    logic rst = 1, in_valid = 0, in_ready, out_valid, out_ready = 1;
    logic signed [31:0] raw_accumulator = 0, weight_sum = 0;
    logic signed [31:0] corrected_accumulator;
    logic [4:0] in_channel_id = 0, out_channel_id;
    logic out_overflow;
    pe8_result_correction dut (.*);

    // Independent one-entry scoreboard: check the old output BEFORE updating
    // the expected entry for a simultaneous output/input handshake.
    bit pending = 0;
    integer expected_value, checks = 0, received = 0, discarded = 0;
    bit expected_overflow;
    logic [4:0] expected_channel;
    longint signed wide_reference;

    always @(posedge clk) begin
        if (rst) begin
            if (pending) discarded = discarded + 1;
            pending = 0;
            #1;
            if (out_valid || in_ready || corrected_accumulator != 0 ||
                out_overflow || out_channel_id != 0) $fatal(1, "Reset failed");
        end else begin
            if (out_valid !== pending) $fatal(1, "Output valid mismatch");
            if (pending) begin
                checks = checks + 1;
                if (corrected_accumulator !== expected_value ||
                    out_channel_id !== expected_channel ||
                    out_overflow !== expected_overflow)
                    $fatal(1, "Result mismatch: got=%0d expected=%0d channel=%0d",
                           corrected_accumulator, expected_value, out_channel_id);
            end
            if (out_valid && out_ready) begin
                pending = 0;
                received = received + 1;
            end
            if (in_valid && in_ready) begin
                if (pending) $fatal(1, "Overwrote a stalled output");
                wide_reference = longint'(raw_accumulator) + longint'(weight_sum);
                expected_overflow = 0;
                if (wide_reference > 64'sd2147483647) begin
                    expected_value = 32'sh7fffffff;
                    expected_overflow = 1;
                end else if (wide_reference < -64'sd2147483648) begin
                    expected_value = 32'sh80000000;
                    expected_overflow = 1;
                end else expected_value = int'(wide_reference);
                expected_channel = in_channel_id;
                pending = 1;
            end
        end
    end

    // Return at the falling edge after acceptance. Inputs remain stable while
    // backpressured; the following send can run on the very next rising edge.
    task automatic send(input integer raw, ws, channel);
        if (channel < 0 || channel > 31) $fatal(1, "Invalid test channel");
        raw_accumulator = raw;
        weight_sum = ws;
        in_channel_id = 5'(channel);
        in_valid = 1;
        @(posedge clk);
        while (!in_ready) @(posedge clk);
        @(negedge clk);
        in_valid = 0;
    endtask

    task automatic vector_test(input integer k, mode, channel);
        integer a, w, raw, ws, direct;
        raw = 0; ws = 0; direct = 0;
        for (integer i = 0; i < k; i = i + 1) begin
            case (mode)
                0: a = 127;
                1: a = 128;
                2: a = (i % 2 == 0) ? 0 : 255;
                default: a = (73*i + 29*channel) % 256;
            endcase
            w = (mode == 2) ? ((i % 2 == 0) ? -128 : 127)
                            : ((37*i + 19*channel) % 256) - 128;
            raw = raw + (a-128)*w;
            ws = ws + w;
            direct = direct + (a-127)*w;
        end
        // Separate model formula, in addition to the streaming scoreboard.
        send(raw, ws, channel);
        if (corrected_accumulator !== direct || out_overflow)
            $fatal(1, "Direct model mismatch K=%0d mode=%0d", k, mode);
    endtask

    initial begin
        #100000;
        $fatal(1, "Watchdog timeout");
    end

    initial begin
        repeat (2) @(negedge clk);
        rst = 0;
        $display("TEST arithmetic and INT32 saturation boundaries");
        send(-12, -1, 0);
        send(0, 0, 1);
        send(32'sh7fffffff, 0, 2);
        send(32'sh80000000, 0, 3);
        send(32'sh7fffffff, 1, 4);
        send(32'sh80000000, -1, 5);
        send(32'sh7fffffff, 32'sh7fffffff, 6);
        send(32'sh80000000, 32'sh80000000, 7);
        send(32'sh7fffffff, 32'sh80000000, 8);
        $display("TEST direct model: K=9/32/144, A=127/128/edges/mixed");
        for (integer mode = 0; mode < 4; mode = mode + 1) begin
            vector_test(9, mode, mode);
            vector_test(32, mode, mode+12);
            vector_test(144, mode, mode+24);
        end
        $display("TEST continuous stream, all channels, input bubbles");
        for (integer j = 0; j < 64; j = j + 1) begin
            send(j*193-6000, 3000-j*97, j%32);
            if (j%5 == 0) repeat (2) @(negedge clk);
        end
        $display("TEST backpressure and simultaneous consume/replace");
        repeat (2) @(negedge clk);
        out_ready = 0;
        send(100, -20, 31); // Empty stage can accept even if downstream stalls.
        raw_accumulator = -300;
        weight_sum = 17;
        in_channel_id = 9;
        in_valid = 1;
        repeat (5) begin
            @(negedge clk);
            if (in_ready) $fatal(1, "Full stage accepted during stall");
        end
        out_ready = 1;
        @(negedge clk);
        in_valid = 0;
        repeat (2) @(negedge clk);
        $display("TEST synchronous reset discards pending output");
        out_ready = 0;
        send(999, 1, 30);
        rst = 1;
        repeat (2) @(negedge clk);
        rst = 0;
        out_ready = 1;
        send(-999, -1, 10);
        repeat (3) @(negedge clk);
        if (pending || out_valid || discarded != 1 || received != 88)
            $fatal(1, "Transaction count mismatch received=%0d discarded=%0d", received, discarded);
        $display("PASS: pe8_result_correction received=%0d discarded=%0d output_checks=%0d",
                 received, discarded, checks);
        $finish;
    end
endmodule
